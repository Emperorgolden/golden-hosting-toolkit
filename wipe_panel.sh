#!/bin/bash

# === COLORS ===
RED='\033[1;31m'
GRN='\033[1;32m'
YEL='\033[1;33m'
BLU='\033[1;34m'
MAG='\033[1;35m'
RST='\033[0m'

# === MEDIUM-SIZE BANNER ===
function banner() {
  clear
  echo -e "${YEL}╔═══════════════════════════════════════╗${RST}"
  echo -e "${RED}║     GOLDEN HOSTING TOOLKIT v1.0       ║${RST}"
  echo -e "${BLU}║   Advanced VPS Panel Wipe & Update    ║${RST}"
  echo -e "${YEL}╚═══════════════════════════════════════╝${RST}"
  echo
}

banner

# === Root Check ===
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

# === MYSQL Setup ===
echo -e "${MAG}[+] Connecting to MySQL...${RST}"

MYSQL_CMD="mysql -u root -p"

read -s -p "Enter MySQL root password: " MYSQL_PASS
echo

function safe_exec() {
    CMD="$1"
    OUTPUT=$($MYSQL_CMD -p"$MYSQL_PASS" -e "$CMD" 2>&1)
    if [[ "$OUTPUT" == *"ERROR 1396"* ]]; then
        echo -e "${YEL}[!] Skipped nonexistent user.${RST}"
    elif [[ "$OUTPUT" == *"ERROR"* ]]; then
        echo -e "${RED}[!] MySQL error: $OUTPUT${RST}"
    fi
}

function nuke_mysql() {
    DBS=$($MYSQL_CMD -p"$MYSQL_PASS" -N -e "SHOW DATABASES;" 2>/dev/null)
    USERS=$($MYSQL_CMD -p"$MYSQL_PASS" -N -e "SELECT User, Host FROM mysql.user WHERE User NOT IN ('mysql.sys','root','mysql.session','debian-sys-maint');" 2>/dev/null)

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

nuke_mysql

# === PANEL PURGE ===
echo -e "${MAG}[+] Killing panel services and deleting files...${RST}"

SERVICES=("pteroq" "pterodactyl" "wings")
for svc in "${SERVICES[@]}"; do
    if systemctl list-units --type=service | grep -q "$svc"; then
        echo -e "${YEL}[*] Disabling service: $svc${RST}"
        systemctl stop "$svc"
        systemctl disable "$svc"
        rm -f "/etc/systemd/system/$svc.service"
    fi
done

DIRS=("/var/www/pterodactyl" "/etc/pterodactyl" "/var/lib/pterodactyl" "/srv/daemon" "/srv/wings")
for dir in "${DIRS[@]}"; do
    if [ -d "$dir" ]; then
        echo -e "${YEL}[*] Removing directory: $dir${RST}"
        rm -rf "$dir"
    fi
done

rm -f /etc/nginx/sites-enabled/pterodactyl.conf /etc/nginx/sites-available/pterodactyl.conf
rm -f /etc/apache2/sites-enabled/panel.conf /etc/apache2/sites-available/panel.conf
find /var/log -name "*pterodactyl*" -exec rm -f {} \;

# === Final Verifications ===
echo -e "${BLU}[+] Final database and user check...${RST}"

LEFT_DB=$($MYSQL_CMD -p"$MYSQL_PASS" -N -e "SHOW DATABASES;" 2>/dev/null | grep -v -E 'mysql|information_schema|performance_schema|sys')
LEFT_USERS=$($MYSQL_CMD -p"$MYSQL_PASS" -N -e "SELECT User FROM mysql.user WHERE User NOT IN ('mysql.sys','root','mysql.session','debian-sys-maint');" 2>/dev/null)

if [ -z "$LEFT_DB" ] && [ -z "$LEFT_USERS" ]; then
    echo -e "${GRN}[✓] Golden Hosting Toolkit: All clean. System sanitized.${RST}"
else
    echo -e "${RED}[!] Warning: Residuals found.${RST}"
    echo -e "${YEL}Databases:${RST} $LEFT_DB"
    echo -e "${YEL}Users:${RST} $LEFT_USERS"
fi

update_system
