#!/bin/bash

# === COLORS ===
RED='\033[1;31m'
GRN='\033[1;32m'
YEL='\033[1;33m'
BLU='\033[1;34m'
MAG='\033[1;35m'
RST='\033[0m'

# === BANNER ===
function banner() {
  clear
  echo -e "${YEL}╔═══════════════════════════════════════╗${RST}"
  echo -e "${RED}║     GOLDEN HOSTING TOOLKIT v2.2       ║${RST}"
  echo -e "${BLU}║   Advanced VPS Panel Wipe & Cleanup   ║${RST}"
  echo -e "${YEL}╚═══════════════════════════════════════╝${RST}"
  echo
}

banner

# === ROOT CHECK ===
if [ "$(id -u)" -ne 0 ]; then
  echo -e "${RED}[!] Must be run as root.${RST}"
  exit 1
fi

# === SYSTEM UPDATE ===
function update_system() {
  echo -e "${BLU}[+] Checking for system updates...${RST}"
  apt update -y && apt upgrade -y
}

update_system

# === MYSQL AUTH ===
echo -e "${MAG}[+] Testing MySQL root connection...${RST}"
if mysql -u root -e "SELECT VERSION();" >/dev/null 2>&1; then
  MYSQL_CMD="mysql -u root"
  echo -e "${GRN}[✓] Connected using no password.${RST}"
else
  read -s -p "Enter MySQL root password: " MYSQL_PASS
  echo
  MYSQL_CMD="mysql -u root -p$MYSQL_PASS"
  $MYSQL_CMD -e "SELECT VERSION();" >/dev/null 2>&1 || {
    echo -e "${RED}[!] Invalid MySQL credentials.${RST}"
    exit 1
  }
fi

# === SAFE SQL EXEC ===
function safe_exec() {
  local SQL="$1"
  local OUTPUT=$($MYSQL_CMD -e "$SQL" 2>&1)
  [[ "$OUTPUT" =~ ERROR ]] && echo -e "${RED}[!] MySQL error:\n$SQL\n$OUTPUT${RST}"
}

# === FIX INVALID DEFINERS ===
function fix_invalid_definers() {
  echo -e "${MAG}[+] Checking for invalid DEFINER entries...${RST}"
  local DEFINED=$($MYSQL_CMD -N -e "SELECT CONCAT(ROUTINE_TYPE, ' ', ROUTINE_SCHEMA, '.', ROUTINE_NAME, ' DEFINER ', DEFINER) FROM information_schema.ROUTINES WHERE DEFINER NOT IN (SELECT CONCAT(User, '@', Host) FROM mysql.user);")
  
  if [[ -z "$DEFINED" ]]; then
    echo -e "${GRN}[✓] No invalid DEFINERS found.${RST}"
    return
  fi

  echo -e "${YEL}[*] Fixing DEFINERs...${RST}"
  while read -r entry; do
    TYPE=$(echo "$entry" | cut -d' ' -f1)
    DB=$(echo "$entry" | cut -d' ' -f2 | cut -d'.' -f1)
    NAME=$(echo "$entry" | cut -d'.' -f2 | cut -d' ' -f1)

    SQL="ALTER $TYPE \`$DB\`.\`$NAME\` DEFINER='root@localhost';"
    safe_exec "$SQL"
  done <<< "$DEFINED"
}

fix_invalid_definers

# === MYSQL CLEANUP ===
function nuke_mysql() {
  echo -e "${BLU}[+] Purging unwanted MySQL users and databases...${RST}"
  DBS=$($MYSQL_CMD -N -e "SHOW DATABASES;")
  for DB in $DBS; do
    [[ "$DB" =~ ^(mysql|information_schema|performance_schema|sys)$ ]] && continue
    echo -e "${YEL}[*] Dropping database: $DB${RST}"
    safe_exec "DROP DATABASE \`$DB\`;"
  done

  USERS=$($MYSQL_CMD -N -e "SELECT CONCAT(\"'\", User, \"'@'\", Host, \"'\") FROM mysql.user WHERE User NOT IN ('mysql.sys','root','mysql.session','debian-sys-maint');")
  for U in $USERS; do
    echo -e "${YEL}[*] Dropping user: $U${RST}"
    safe_exec "DROP USER $U;"
  done

  safe_exec "FLUSH PRIVILEGES;"
}

nuke_mysql

# === PANEL FILE CLEANUP ===
function wipe_panel_files() {
  echo -e "${MAG}[+] Killing panel services and wiping files...${RST}"
  SERVICES=("pteroq" "pterodactyl" "wings")
  for svc in "${SERVICES[@]}"; do
    systemctl stop "$svc" 2>/dev/null
    systemctl disable "$svc" 2>/dev/null
    rm -f "/etc/systemd/system/$svc.service"
  done

  DIRS=("/var/www/pterodactyl" "/etc/pterodactyl" "/var/lib/pterodactyl" "/srv/daemon" "/srv/wings" "/var/log/pterodactyl")
  for dir in "${DIRS[@]}"; do
    if [ -d "$dir" ]; then
      echo -e "${YEL}[*] Removing directory: $dir${RST}"
      rm -rf "$dir"
    fi
  done

  rm -f /etc/nginx/sites-enabled/pterodactyl.conf /etc/nginx/sites-available/pterodactyl.conf
  rm -f /etc/apache2/sites-enabled/panel.conf /etc/apache2/sites-available/panel.conf
  find /var/log -name "*pterodactyl*" -exec rm -f {} \;
}

wipe_panel_files

# === DOCKER CLEANUP ===
function docker_cleanup() {
  echo -e "${MAG}[+] Cleaning up Docker containers and volumes...${RST}"

  docker ps -q | xargs -r docker stop
  docker ps -aq | xargs -r docker rm -f
  docker volume ls -q | xargs -r docker volume rm
  docker network prune -f
  docker image prune -af
  docker builder prune -f

  echo -e "${GRN}[✓] Docker environment cleaned.${RST}"
}

docker_cleanup

# === RECREATE ESSENTIAL USERS ===
function recreate_admin_users() {
  echo -e "${MAG}[+] Ensuring 'admin' MySQL user exists properly...${RST}"
  HOSTS=("localhost" "127.0.0.1" "$(hostname -f)")
  for H in "${HOSTS[@]}"; do
    CHECK=$($MYSQL_CMD -N -e "SELECT 1 FROM mysql.user WHERE User='admin' AND Host='$H';" 2>/dev/null)
    if [[ -z "$CHECK" ]]; then
      echo -e "${YEL}[*] Creating user: 'admin'@'$H'${RST}"
      safe_exec "CREATE USER 'admin'@'$H' IDENTIFIED BY 'admin';"
    else
      echo -e "${GRN}[✓] User exists: 'admin'@'$H'${RST}"
    fi
  done
}

recreate_admin_users

# === FINAL REPORT ===
echo -e "${BLU}[+] Final database/user check...${RST}"
LEFT_DB=$($MYSQL_CMD -N -e "SHOW DATABASES;" | grep -v -E 'mysql|information_schema|performance_schema|sys')
LEFT_USERS=$($MYSQL_CMD -N -e "SELECT CONCAT(User, '@', Host) FROM mysql.user WHERE User NOT IN ('mysql.sys','root','mysql.session','debian-sys-maint','admin');")

if [ -z "$LEFT_DB" ] && [ -z "$LEFT_USERS" ]; then
  echo -e "${GRN}[✓] Golden Hosting Toolkit: All clean. System sanitized.${RST}"
else
  echo -e "${RED}[!] Residuals found:${RST}"
  [[ -n "$LEFT_DB" ]] && echo -e "${YEL}Databases:${RST}\n$LEFT_DB"
  [[ -n "$LEFT_USERS" ]] && echo -e "${YEL}Users:${RST}\n$LEFT_USERS"
fi

update_system
