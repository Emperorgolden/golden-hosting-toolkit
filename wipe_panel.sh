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
  echo -e "${RED}║     GOLDEN HOSTING TOOLKIT v2.0       ║${RST}"
  echo -e "${BLU}║   Advanced VPS Panel Wipe & Cleanup   ║${RST}"
  echo -e "${YEL}╚═══════════════════════════════════════╝${RST}"
  echo
}

banner

# === ROOT CHECK ===
if [ "$(id -u)" -ne 0 ]; then
    echo -e "${RED}[!] Must be run as root. Exiting.${RST}"
    exit 1
fi

# === SYSTEM UPDATE ===
function update_system() {
    echo -e "${BLU}[+] Checking for system updates...${RST}"
    if command -v apt >/dev/null; then
        apt update -y && apt upgrade -y
    elif command -v yum >/dev/null; then
        yum update -y
    elif command -v dnf >/dev/null; then
        dnf upgrade -y
    else
        echo -e "${RED}[!] Unknown package manager. Skipping update.${RST}"
    fi
}

update_system

# === MYSQL AUTH ===
echo -e "${MAG}[+] Testing MySQL root connection without password...${RST}"
if mysql -u root -e "SELECT VERSION();" >/dev/null 2>&1; then
    MYSQL_CMD="mysql -u root"
    echo -e "${GRN}[✓] Connected using no password.${RST}"
else
    echo -e "${YEL}[!] No passwordless access. Prompting for MySQL root password.${RST}"
    read -s -p "Enter MySQL root password: " MYSQL_PASS
    echo
    MYSQL_CMD="mysql -u root -p$MYSQL_PASS"

    if ! $MYSQL_CMD -e "SELECT VERSION();" >/dev/null 2>&1; then
        echo -e "${RED}[X] Unable to authenticate with provided password. Exiting.${RST}"
        exit 1
    else
        echo -e "${GRN}[✓] Connected using password.${RST}"
    fi
fi

# === SAFE EXECUTION ===
function safe_exec() {
    CMD="$1"
    OUTPUT=$($MYSQL_CMD -e "$CMD" 2>&1)
    if [[ "$OUTPUT" == *"ERROR 1396"* ]]; then
        echo -e "${YEL}[!] Skipped: $CMD (User exists or corrupted)${RST}"
    elif [[ "$OUTPUT" == *"ERROR"* ]]; then
        echo -e "${RED}[!] MySQL error:\n$CMD\n--------------\n$OUTPUT${RST}"
    fi
}

# === DEEP MYSQL WIPE ===
function nuke_mysql() {
    DBS=$($MYSQL_CMD -N -e "SHOW DATABASES;" 2>/dev/null)
    USERS=$($MYSQL_CMD -N -e "SELECT User, Host FROM mysql.user WHERE User NOT IN ('mysql.sys','root','mysql.session','debian-sys-maint','admin');" 2>/dev/null || echo "")

    for DB in $DBS; do
        if [[ "$DB" != "mysql" && "$DB" != "information_schema" && "$DB" != "performance_schema" && "$DB" != "sys" ]]; then
            echo -e "${YEL}[*] Dropping DB: $DB${RST}"
            safe_exec "DROP DATABASE \\`$DB\\`;"
        fi
    done

    while read -r USER HOST; do
        if [[ -n "$USER" && -n "$HOST" ]]; then
            echo -e "${YEL}[*] Dropping user: '$USER'@'$HOST'${RST}"
            safe_exec "DROP USER IF EXISTS '$USER'@'$HOST';"
        fi
    done <<< "$USERS"

    safe_exec "FLUSH PRIVILEGES;"
    echo -e "${GRN}[+] MySQL purge complete.${RST}"
}

nuke_mysql

# === FIX DEFINER ERRORS ===
function fix_definers() {
    echo -e "${MAG}[+] Checking for invalid DEFINER entries...${RST}"
    DEFINERS=$($MYSQL_CMD -N -e "SELECT CONCAT(ROUTINE_TYPE, ' ', ROUTINE_SCHEMA, '.', ROUTINE_NAME) FROM information_schema.ROUTINES WHERE DEFINER LIKE 'mariadb.sys@localhost';" 2>/dev/null)
    for ITEM in $DEFINERS; do
        TYPE=$(echo $ITEM | cut -d' ' -f1)
        FULL=$(echo $ITEM | cut -d' ' -f2)
        echo -e "${YEL}[*] Fixing DEFINER on: $FULL${RST}"
        safe_exec "DROP $TYPE $FULL;"
    done
}

fix_definers

# === REMOVE PANEL FILES & SERVICES ===
echo -e "${MAG}[+] Killing panel services and purging files...${RST}"
SERVICES=("pteroq" "pterodactyl" "wings")
for svc in "${SERVICES[@]}"; do
    systemctl stop "$svc" 2>/dev/null
    systemctl disable "$svc" 2>/dev/null
    rm -f "/etc/systemd/system/$svc.service"
    systemctl daemon-reload
done

DIRS=("/var/www/pterodactyl" "/etc/pterodactyl" "/var/lib/pterodactyl" "/srv/daemon" "/srv/wings")
for dir in "${DIRS[@]}"; do
    [ -d "$dir" ] && echo -e "${YEL}[*] Removing directory: $dir${RST}" && rm -rf "$dir"

done
rm -f /etc/nginx/sites-enabled/pterodactyl.conf /etc/nginx/sites-available/pterodactyl.conf
rm -f /etc/apache2/sites-enabled/panel.conf /etc/apache2/sites-available/panel.conf
find /var/log -name "*pterodactyl*" -exec rm -rf {} +

# === DOCKER CLEANUP ===
echo -e "${MAG}[+] Cleaning up Docker containers...${RST}"
docker rm -f $(docker ps -aq) 2>/dev/null
rm -rf /var/lib/docker/containers/*

# === RECREATE ADMIN USERS ===
function recreate_admin_users() {
  echo -e "${MAG}[+] Ensuring 'admin' MySQL user exists properly...${RST}"
  HOSTS=("localhost" "127.0.0.1" "$(hostname -f)" "private")
  for H in "${HOSTS[@]}"; do
    echo -e "${YEL}[*] Dropping user if exists: 'admin'@'$H'${RST}"
    safe_exec "DROP USER IF EXISTS 'admin'@'$H';"
    echo -e "${YEL}[*] Creating user: 'admin'@'$H'${RST}"
    safe_exec "CREATE USER 'admin'@'$H' IDENTIFIED BY 'admin';"
    safe_exec "GRANT ALL PRIVILEGES ON *.* TO 'admin'@'$H' WITH GRANT OPTION;"
  done
  safe_exec "FLUSH PRIVILEGES;"
}

recreate_admin_users

# === VERIFY FINAL CLEANUP ===
echo -e "${BLU}[+] Final database/user check...${RST}"
LEFT_DB=$($MYSQL_CMD -N -e "SHOW DATABASES;" 2>/dev/null | grep -v -E 'mysql|information_schema|performance_schema|sys')
LEFT_USERS=$($MYSQL_CMD -N -e "SELECT CONCAT(User, '@', Host) FROM mysql.user WHERE User NOT IN ('mysql.sys','root','mysql.session','debian-sys-maint','admin');" 2>/dev/null || echo "")

if [ -z "$LEFT_DB" ] && [ -z "$LEFT_USERS" ]; then
    echo -e "${GRN}[✓] Golden Hosting Toolkit: All clean. System sanitized.${RST}"
else
    echo -e "${RED}[!] Residuals found:${RST}"
    echo -e "${YEL}Databases:${RST} $LEFT_DB"
    echo -e "${YEL}Users:${RST} $LEFT_USERS"
fi

update_system
