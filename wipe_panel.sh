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
    apt update -y && apt upgrade -y
}

update_system

# === MYSQL AUTO-CONNECT ===
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
        echo -e "${RED}[X] Cannot authenticate to MySQL. Exiting.${RST}"
        exit 1
    fi
    echo -e "${GRN}[✓] Connected using password.${RST}"
fi

# === SAFE MYSQL EXEC ===
function safe_exec() {
    local query="$1"
    OUTPUT=$($MYSQL_CMD -e "$query" 2>&1)
    if [[ "$OUTPUT" == *"ERROR"* ]]; then
        echo -e "${RED}[!] MySQL error:\n$query\n$OUTPUT${RST}"
    fi
}

# === FIX DEFINER ISSUES ===
function fix_definers() {
    echo -e "${MAG}[+] Checking for invalid DEFINER entries...${RST}"
    DEFINERS=$($MYSQL_CMD -N -e "SELECT CONCAT(ROUTINE_TYPE, ' ', ROUTINE_SCHEMA, '.', ROUTINE_NAME) FROM information_schema.ROUTINES WHERE DEFINER NOT LIKE '%@localhost' AND ROUTINE_SCHEMA NOT IN ('mysql', 'performance_schema', 'information_schema', 'sys');")

    for item in $DEFINERS; do
        TYPE=$(echo $item | awk '{print $1}')
        NAME=$(echo $item | awk '{print $2}')
        FIX="ALTER $TYPE $NAME DEFINER='root@localhost';"
        safe_exec "$FIX"
    done
}

# === MYSQL NUKE ===
function nuke_mysql() {
    DBS=$($MYSQL_CMD -N -e "SHOW DATABASES;" 2>/dev/null)
    USERS=$($MYSQL_CMD -N -e "SELECT User, Host FROM mysql.user WHERE User NOT IN ('mysql.sys','root','mysql.session','debian-sys-maint','admin');" 2>/dev/null)

    for DB in $DBS; do
        if [[ "$DB" != "mysql" && "$DB" != "information_schema" && "$DB" != "performance_schema" && "$DB" != "sys" ]]; then
            echo -e "${YEL}[*] Dropping DB: $DB${RST}"
            safe_exec "DROP DATABASE \`$DB\`;"
        fi
    done

    while read -r USER HOST; do
        if [[ -n "$USER" && -n "$HOST" ]]; then
            echo -e "${YEL}[*] Dropping user: '$USER'@'$HOST'${RST}"
            safe_exec "DROP USER '$USER'@'$HOST';"
        fi
    done <<< "$USERS"

    safe_exec "FLUSH PRIVILEGES;"
    echo -e "${GRN}[+] MySQL purge complete.${RST}"
}

# === ENSURE ADMIN USER ===
function ensure_admin_user() {
    echo -e "${MAG}[+] Ensuring 'admin' MySQL user exists properly...${RST}"
    HOSTS=("localhost" "127.0.0.1" "$(hostname -f)")
    for host in "${HOSTS[@]}"; do
        echo -e "${YEL}[*] Creating user: 'admin'@$host${RST}"
        $MYSQL_CMD -e "DROP USER IF EXISTS 'admin'@'$host';" 2>/dev/null
        $MYSQL_CMD -e "CREATE USER 'admin'@'$host' IDENTIFIED BY 'admin';" 2>/dev/null
        $MYSQL_CMD -e "GRANT ALL PRIVILEGES ON *.* TO 'admin'@'$host' WITH GRANT OPTION;" 2>/dev/null
    done
    $MYSQL_CMD -e "FLUSH PRIVILEGES;"
}

# === KILL PANEL SERVICES ===
echo -e "${MAG}[+] Killing panel services and purging files...${RST}"
SERVICES=("pteroq" "pterodactyl" "wings")
for svc in "${SERVICES[@]}"; do
    systemctl stop "$svc" 2>/dev/null
    systemctl disable "$svc" 2>/dev/null
    rm -f "/etc/systemd/system/$svc.service"
done

DIRS=("/var/www/pterodactyl" "/etc/pterodactyl" "/var/lib/pterodactyl" "/srv/daemon" "/srv/wings")
for dir in "${DIRS[@]}"; do
    [ -d "$dir" ] && rm -rf "$dir"
done

rm -f /etc/nginx/sites-enabled/pterodactyl.conf /etc/nginx/sites-available/pterodactyl.conf
rm -f /etc/apache2/sites-enabled/panel.conf /etc/apache2/sites-available/panel.conf
find /var/log -name "*pterodactyl*" -exec rm -rf {} + 2>/dev/null

# === DOCKER WIPE ===
echo -e "${MAG}[+] Cleaning Docker containers, volumes, images...${RST}"
docker rm -f $(docker ps -aq) 2>/dev/null
docker volume rm $(docker volume ls -q) 2>/dev/null
docker image rm $(docker images -q) 2>/dev/null

# === EXECUTION ===
fix_definers
nuke_mysql
ensure_admin_user

# === VERIFY ===
echo -e "${BLU}[+] Final database/user check...${RST}"
LEFT_DB=$($MYSQL_CMD -N -e "SHOW DATABASES;" 2>/dev/null | grep -v -E 'mysql|information_schema|performance_schema|sys')
LEFT_USERS=$($MYSQL_CMD -N -e "SELECT User FROM mysql.user WHERE User NOT IN ('mysql.sys','root','mysql.session','debian-sys-maint','admin');" 2>/dev/null)

if [ -z "$LEFT_DB" ] && [ -z "$LEFT_USERS" ]; then
    echo -e "${GRN}[✓] Golden Hosting Toolkit: All clean. System sanitized.${RST}"
else
    echo -e "${RED}[!] Residuals found:${RST}"
    echo -e "${YEL}Databases:${RST} $LEFT_DB"
    echo -e "${YEL}Users:${RST} $LEFT_USERS"
fi

update_system
