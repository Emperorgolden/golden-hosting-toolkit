#!/bin/bash

# === COLORIZED BANNER ===
function banner() {
  clear
  echo -e "\033[1;33m███████╗ ██████╗ ██╗     ██████╗ ███████╗███╗   ██╗\033[0m"
  echo -e "\033[1;31m██╔════╝██╔═══██╗██║     ██╔══██╗██╔════╝████╗  ██║\033[0m"
  echo -e "\033[1;34m█████╗  ██║   ██║██║     ██║  ██║█████╗  ██╔██╗ ██║\033[0m"
  echo -e "\033[1;31m██╔══╝  ██║   ██║██║     ██║  ██║██╔══╝  ██║╚██╗██║\033[0m"
  echo -e "\033[1;33m██║     ╚██████╔╝███████╗██████╔╝███████╗██║ ╚████║\033[0m"
  echo -e "\033[1;34m╚═╝      ╚═════╝ ╚══════╝╚═════╝ ╚══════╝╚═╝  ╚═══╝\033[0m"
  echo -e "         \033[1;35mGolden Hosting Service Toolkit\033[0m"
  echo
}

banner

# === Root Check ===
if [ "$(id -u)" -ne 0 ]; then
    echo "[!] Must be run as root. Exiting."
    exit 1
fi

# === SYSTEM UPDATE (Pre & Post) ===
function update_system() {
    echo "[+] Checking for system updates..."
    if command -v apt >/dev/null; then
        apt update -y && apt upgrade -y
    elif command -v yum >/dev/null; then
        yum update -y
    elif command -v dnf >/dev/null; then
        dnf upgrade -y
    else
        echo "[!] Unknown package manager. Skipping update."
    fi
}

update_system

# === MYSQL Nuker ===
echo "[+] Connecting to MySQL..."

MYSQL_CMD="mysql -u root -p"

read -s -p "Enter MySQL root password: " MYSQL_PASS
echo

function safe_exec() {
    CMD="$1"
    OUTPUT=$($MYSQL_CMD -p"$MYSQL_PASS" -e "$CMD" 2>&1)
    if [[ "$OUTPUT" == *"ERROR 1396"* ]]; then
        echo "[!] Skipped nonexistent user or duplicate error."
    elif [[ "$OUTPUT" == *"ERROR"* ]]; then
        echo "[!] MySQL error: $OUTPUT"
    fi
}

function nuke_mysql() {
    DBS=$($MYSQL_CMD -p"$MYSQL_PASS" -N -e "SHOW DATABASES;" 2>/dev/null)
    USERS=$($MYSQL_CMD -p"$MYSQL_PASS" -N -e "SELECT User, Host FROM mysql.user WHERE User NOT IN ('mysql.sys','root','mysql.session','debian-sys-maint');" 2>/dev/null)

    for DB in $DBS; do
        if [[ "$DB" != "mysql" && "$DB" != "information_schema" && "$DB" != "performance_schema" && "$DB" != "sys" ]]; then
            echo "[*] Dropping DB: $DB"
            safe_exec "DROP DATABASE \`$DB\`;"
        fi
    done

    while read -r USER HOST; do
        if [[ -n "$USER" && -n "$HOST" ]]; then
            echo "[*] Dropping user: '$USER'@'$HOST'"
            safe_exec "DROP USER '$USER'@'$HOST';"
        fi
    done <<< "$USERS"

    safe_exec "FLUSH PRIVILEGES;"
    echo "[+] MySQL purge complete."
}

nuke_mysql

# === Service and File Destruction ===
echo "[+] Killing panel daemons and purging directories..."

SERVICES=("pteroq" "pterodactyl" "wings")
for svc in "${SERVICES[@]}"; do
    if systemctl list-units --type=service | grep -q "$svc"; then
        echo "[*] Stopping service: $svc"
        systemctl stop "$svc"
        systemctl disable "$svc"
        rm -f "/etc/systemd/system/$svc.service"
    fi
done

DIRS=("/var/www/pterodactyl" "/etc/pterodactyl" "/var/lib/pterodactyl" "/srv/daemon" "/srv/wings")
for dir in "${DIRS[@]}"; do
    if [ -d "$dir" ]; then
        echo "[*] Removing directory: $dir"
        rm -rf "$dir"
    fi
done

rm -f /etc/nginx/sites-enabled/pterodactyl.conf /etc/nginx/sites-available/pterodactyl.conf
rm -f /etc/apache2/sites-enabled/panel.conf /etc/apache2/sites-available/panel.conf
find /var/log -name "*pterodactyl*" -exec rm -f {} \;

# === Final Check ===
echo "[+] Verifying..."

LEFT_DB=$($MYSQL_CMD -p"$MYSQL_PASS" -N -e "SHOW DATABASES;" 2>/dev/null | grep -v -E 'mysql|information_schema|performance_schema|sys')
LEFT_USERS=$($MYSQL_CMD -p"$MYSQL_PASS" -N -e "SELECT User FROM mysql.user WHERE User NOT IN ('mysql.sys','root','mysql.session','debian-sys-maint');" 2>/dev/null)

if [ -z "$LEFT_DB" ] && [ -z "$LEFT_USERS" ]; then
    echo -e "\033[1;32m[✓] Golden Hosting Toolkit: All clean. System sanitized.\033[0m"
else
    echo -e "\033[1;31m[!] Residual MySQL objects detected:\033[0m"
    echo "$LEFT_DB"
    echo "$LEFT_USERS"
fi

update_system
