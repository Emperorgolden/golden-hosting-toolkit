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
  echo -e "${BLU}║     Deep MySQL + Panel System Wipe    ║${RST}"
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
echo -e "${MAG}[+] Checking MySQL root access...${RST}"
if mysql -u root -e "SELECT VERSION();" >/dev/null 2>&1; then
    MYSQL_CMD="mysql -u root"
    echo -e "${GRN}[✓] Connected without password.${RST}"
else
    read -s -p "Enter MySQL root password: " MYSQL_PASS
    echo
    MYSQL_CMD="mysql -u root -p$MYSQL_PASS"
    if ! $MYSQL_CMD -e "SELECT VERSION();" >/dev/null 2>&1; then
        echo -e "${RED}[X] Incorrect password. Exiting.${RST}"
        exit 1
    fi
fi

# === MYSQL DEEP CLEAN ===
function deep_mysql_clean() {
    echo -e "${MAG}[+] Performing deep MySQL cleanup...${RST}"
    DBS=$($MYSQL_CMD -N -e "SHOW DATABASES;")
    for DB in $DBS; do
        case "$DB" in
            mysql|performance_schema|information_schema|sys) continue ;;
            *)
                echo -e "${YEL}[*] Dropping database: $DB${RST}"
                $MYSQL_CMD -e "DROP DATABASE \`$DB\`;"
                ;;
        esac
    done

    USERS=$($MYSQL_CMD -N -e "SELECT CONCAT(\"'\",User,\"'@'\",Host,\"'\") FROM mysql.user WHERE User NOT IN ('mysql.sys','root','mysql.session','debian-sys-maint');")
    for user in $USERS; do
        echo -e "${YEL}[*] Dropping user: $user${RST}"
        $MYSQL_CMD -e "DROP USER $user;"
    done

    $MYSQL_CMD -e "FLUSH PRIVILEGES;"
    echo -e "${GRN}[✓] MySQL cleaned up successfully.${RST}"
}

deep_mysql_clean

# === KILL SERVICES & REMOVE FILES ===
echo -e "${MAG}[+] Stopping and removing Pterodactyl-related services/files...${RST}"
SERVICES=("pteroq" "pterodactyl" "wings")
for svc in "${SERVICES[@]}"; do
    if systemctl list-units --type=service | grep -q "$svc"; then
        echo -e "${YEL}[*] Stopping $svc...${RST}"
        systemctl stop "$svc"
        systemctl disable "$svc"
        rm -f "/etc/systemd/system/$svc.service"
    fi
done

DIRS=("/var/www/pterodactyl" "/etc/pterodactyl" "/var/lib/pterodactyl" "/srv/daemon" "/srv/wings")
for dir in "${DIRS[@]}"; do
    if [ -d "$dir" ]; then
        echo -e "${YEL}[*] Removing: $dir${RST}"
        rm -rf "$dir"
    fi
done

rm -f /etc/nginx/sites-enabled/pterodactyl.conf /etc/nginx/sites-available/pterodactyl.conf
rm -f /etc/apache2/sites-enabled/panel.conf /etc/apache2/sites-available/panel.conf
find /var/log -name "*pterodactyl*" -exec rm -f {} \;

# === VERIFY ===
echo -e "${BLU}[+] Final MySQL check...${RST}"
LEFT_DB=$($MYSQL_CMD -N -e "SHOW DATABASES;" | grep -v -E 'mysql|information_schema|performance_schema|sys')
LEFT_USERS=$($MYSQL_CMD -N -e "SELECT User FROM mysql.user WHERE User NOT IN ('mysql.sys','root','mysql.session','debian-sys-maint');")

if [ -z "$LEFT_DB" ] && [ -z "$LEFT_USERS" ]; then
    echo -e "${GRN}[✓] Everything wiped. No leftovers found.${RST}"
else
    echo -e "${RED}[!] Residuals still found:${RST}"
    echo -e "${YEL}Databases:${RST} $LEFT_DB"
    echo -e "${YEL}Users:${RST} $LEFT_USERS"
fi

update_system
