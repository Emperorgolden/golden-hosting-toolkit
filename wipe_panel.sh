#!/bin/bash

# === COLORS ===
RED='\033[1;31m'
GRN='\033[1;32m'
YEL='\033[1;33m'
BLU='\033[1;34m'
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

# === UPDATE SYSTEM ===
echo -e "${BLU}[+] Checking for system updates...${RST}"
apt update -y && apt upgrade -y

# === MYSQL AUTH ===
echo -e "${BLU}[+] Testing MySQL root connection without password...${RST}"
if mysql -u root -e "SELECT VERSION();" >/dev/null 2>&1; then
    MYSQL_CMD="mysql -u root"
    echo -e "${GRN}[✓] Connected using no password.${RST}"
else
    read -s -p "Enter MySQL root password: " MYSQL_PASS
    echo
    MYSQL_CMD="mysql -u root -p$MYSQL_PASS"
    if ! $MYSQL_CMD -e "SELECT VERSION();" >/dev/null 2>&1; then
        echo -e "${RED}[!] MySQL connection failed. Exiting.${RST}"
        exit 1
    fi
fi

# === FIX INVALID DEFINERS ===
echo -e "${BLU}[+] Checking for invalid DEFINER entries...${RST}"
DEFINERS=$($MYSQL_CMD -N -e "
SELECT CONCAT('ALTER ', ROUTINE_TYPE, ' \`', ROUTINE_SCHEMA, '\`.\`', ROUTINE_NAME, '\` COMMENT \"fixed invalid definer\";')
FROM information_schema.ROUTINES
WHERE DEFINER NOT IN (
  SELECT CONCAT(USER, '@', HOST) FROM mysql.user
);
" 2>/dev/null)

if [[ -z "$DEFINERS" ]]; then
    echo -e "${GRN}[✓] No invalid DEFINERs found.${RST}"
else
    echo -e "${YEL}[*] Fixing DEFINERs...${RST}"
    while read -r SQL; do
        if [[ -n "$SQL" ]]; then
            OUT=$($MYSQL_CMD -e "$SQL" 2>&1)
            if [[ "$OUT" == *"ERROR"* ]]; then
                echo -e "${RED}[!] MySQL error: $SQL${RST}"
                echo -e "${RED}    -> $OUT${RST}"
            else
                echo -e "${GRN}[+] Fixed: $SQL${RST}"
            fi
        fi
    done <<< "$DEFINERS"
fi

# === DELETE NON-SYSTEM USERS & DBS ===
echo -e "${BLU}[+] Cleaning up MySQL users and databases...${RST}"
DBS=$($MYSQL_CMD -N -e "SHOW DATABASES;")
for DB in $DBS; do
  case "$DB" in
    mysql|information_schema|performance_schema|sys) ;;
    *)
      echo -e "${YEL}[*] Dropping DB: $DB${RST}"
      $MYSQL_CMD -e "DROP DATABASE \`$DB\`;" 2>/dev/null
      ;;
  esac
done

USERS=$($MYSQL_CMD -N -e "
SELECT CONCAT(\"'\",User,\"'@'\",Host,\"'\")
FROM mysql.user
WHERE User NOT IN ('root','mysql.sys','mysql.session','debian-sys-maint');
")
for USER in $USERS; do
    echo -e "${YEL}[*] Dropping user: $USER${RST}"
    $MYSQL_CMD -e "DROP USER $USER;" 2>/dev/null
done

$MYSQL_CMD -e "FLUSH PRIVILEGES;"

# === KILL PANEL SERVICES & FILES ===
echo -e "${MAG}[+] Killing panel services and wiping files...${RST}"
SERVICES=("pteroq" "pterodactyl" "wings")
for SVC in "${SERVICES[@]}"; do
    if systemctl list-units --type=service | grep -q "$SVC"; then
        echo -e "${YEL}[*] Stopping $SVC...${RST}"
        systemctl stop "$SVC"
        systemctl disable "$SVC"
        rm -f "/etc/systemd/system/$SVC.service"
    fi
done

DIRS=("/var/www/pterodactyl" "/etc/pterodactyl" "/srv/daemon" "/srv/wings" "/var/lib/pterodactyl")
for DIR in "${DIRS[@]}"; do
    [ -d "$DIR" ] && echo -e "${YEL}[*] Removing $DIR${RST}" && rm -rf "$DIR"
done

rm -f /etc/nginx/sites-enabled/pterodactyl.conf /etc/nginx/sites-available/pterodactyl.conf
find /var/log -name "*pterodactyl*" -exec rm -f {} \;

# === VERIFY CLEANUP ===
echo -e "${BLU}[+] Final verification...${RST}"
LEFT_DB=$($MYSQL_CMD -N -e "SHOW DATABASES;" | grep -v -E 'mysql|information_schema|performance_schema|sys')
LEFT_USERS=$($MYSQL_CMD -N -e "
SELECT CONCAT(User, '@', Host)
FROM mysql.user
WHERE User NOT IN ('root','mysql.sys','mysql.session','debian-sys-maint');
")

if [[ -z "$LEFT_DB" && -z "$LEFT_USERS" ]]; then
    echo -e "${GRN}[✓] MySQL clean complete. System sanitized.${RST}"
else
    echo -e "${RED}[!] Residuals found:${RST}"
    echo -e "${YEL}Databases:${RST} $LEFT_DB"
    echo -e "${YEL}Users:${RST} $LEFT_USERS"
fi
