#!/bin/bash

echo "Golden Hosting Service Toolkit initializing..."

# === Root Check ===
if [ "$(id -u)" -ne 0 ]; then
    echo "[!] Must be run as root. Exiting."
    exit 1
fi

# === SYSTEM UPDATE (Pre & Post Purge) ===
function update_system() {
    echo "[+] Checking for system updates..."
    if command -v apt >/dev/null 2>&1; then
        apt update -y && apt upgrade -y
    elif command -v yum >/dev/null 2>&1; then
        yum update -y
    elif command -v dnf >/dev/null 2>&1; then
        dnf upgrade --refresh -y
    else
        echo "[!] Package manager not found. Skipping updates."
    fi
}

update_system

# === MYSQL Nuclear Protocol ===
echo "[+] Connecting to MySQL..."

MYSQL_CMD="mysql -u root -p"

read -s -p "Enter MySQL root password: " MYSQL_PASS
echo

function nuke_mysql() {
    DBS=$($MYSQL_CMD -p"$MYSQL_PASS" -N -e "SHOW DATABASES;" 2>/dev/null)
    USERS=$($MYSQL_CMD -p"$MYSQL_PASS" -N -e "SELECT User, Host FROM mysql.user WHERE User NOT IN ('mysql.sys','root','mysql.session','debian-sys-maint');" 2>/dev/null)

    for DB in $DBS; do
        if [[ "$DB" != "mysql" && "$DB" != "information_schema" && "$DB" != "performance_schema" && "$DB" != "sys" ]]; then
            echo "[*] Dropping DB: $DB"
            $MYSQL_CMD -p"$MYSQL_PASS" -e "DROP DATABASE \`$DB\`;"
        fi
    done

    while read -r USER HOST; do
        echo "[*] Dropping MySQL user: '$USER'@'$HOST'"
        $MYSQL_CMD -p"$MYSQL_PASS" -e "DROP USER '$USER'@'$HOST';"
    done <<< "$USERS"

    $MYSQL_CMD -p"$MYSQL_PASS" -e "FLUSH PRIVILEGES;"
    echo "[+] MySQL purge complete."
}

nuke_mysql

# === Panel Daemon & File Kill ===
echo "[+] Locating panel remnants..."

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

# === Final Verification ===
echo "[+] Verifying purge..."

LEFT_DB=$($MYSQL_CMD -p"$MYSQL_PASS" -N -e "SHOW DATABASES;" 2>/dev/null | grep -v -E 'mysql|information_schema|performance_schema|sys')
LEFT_USERS=$($MYSQL_CMD -p"$MYSQL_PASS" -N -e "SELECT User FROM mysql.user WHERE User NOT IN ('mysql.sys','root','mysql.session','debian-sys-maint');" 2>/dev/null)

if [ -z "$LEFT_DB" ] && [ -z "$LEFT_USERS" ]; then
    echo "[✓] Databases and users: Clean."
else
    echo "[!] Warning: Residuals detected."
    echo "Databases left:"
    echo "$LEFT_DB"
    echo "Users left:"
    echo "$LEFT_USERS"
fi

# === Final System Update (to hide tracks) ===
update_system

echo "Golden Hosting Service Toolkit: All clean. System up to date and sanitized."
