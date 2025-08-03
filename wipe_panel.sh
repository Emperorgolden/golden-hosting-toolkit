#!/bin/bash

# ================= CONFIGURATION =================
YOUR_NAME="Golden Dev"

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

# Logger
LOG_DIR="/var/log/golden_hosting"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/cleanup_$(date +%Y%m%d_%H%M%S).log"
exec > >(tee -a "$LOG_FILE") 2>&1

# Spinner chars (Chinese characters)
SPIN_CHARS=("运" "行" "中" "请" "等" "待" "加" "载" "完" "成")
TICKS=("⠁" "⠂" "⠄" "⡀" "⢀" "⠠" "⠐" "⠈")

# ================= FUNCTIONS =================
display_header() {
    clear
    echo -e "${PURPLE}╔═══════════════════════════════════════╗"
    echo -e "║     ${YELLOW}GOLDEN HOSTING TOOLKIT v2.3${PURPLE}       ║"
    echo -e "║   ${CYAN}Full Forensic VPS Cleaner & Wiper${PURPLE}  ║"
    echo -e "╚═══════════════════════════════════════╝${NC}"
    echo -e "${BLUE}Operator: ${GREEN}$YOUR_NAME${NC}"
    echo -e "${BLUE}Logfile: ${YELLOW}$LOG_FILE${NC}"
    echo -e "${GREEN}Started: $(date)${NC}\n"
}

loading_spinner() {
    local pid=$1
    local msg=$2
    i=0
    while kill -0 $pid 2>/dev/null; do
        printf "\r${SPIN_CHARS[$((i%${#SPIN_CHARS[@]}))]} ${TICKS[$((i%${#TICKS[@]}))]} ${YELLOW}$msg${NC}"
        sleep 0.2
        ((i++))
    done
    printf "\r${GREEN}✓ $msg completed${NC}                \n"
}

run_task() {
    local name="$1"
    local command="$2"
    echo -e "\n${PURPLE}▶ ${CYAN}$name${NC}"
    bash -c "$command" &
    loading_spinner $! "$name"
}

# ================= DESTRUCTIVE ACTIONS =================

remove_pterodactyl_files() {
    run_task "Removing Pterodactyl Files" "rm -rf /var/www/pterodactyl /etc/pterodactyl /usr/local/bin/wings"
    run_task "Removing Logs" "rm -rf /var/log/pterodactyl"
    run_task "Stopping Services" "systemctl stop wings pteroq.service 2>/dev/null"
    run_task "Disabling Services" "systemctl disable wings pteroq.service 2>/dev/null"
}

remove_mysql_data() {
    if ! command -v mysql &>/dev/null; then
        echo -e "${RED}✗ MySQL not installed. Skipping DB cleanup.${NC}"
        return
    fi
    run_task "Dropping Custom Databases" "mysql -e 'SHOW DATABASES' | grep -Ev '^(mysql|sys|performance_schema|information_schema)$' | xargs -I{} mysql -e \"DROP DATABASE IF EXISTS \`{}\`;\""
    run_task "Removing Custom MySQL Users" "mysql -e \"SELECT User, Host FROM mysql.user WHERE User NOT IN ('mysql.sys','root','debian-sys-maint')\" | awk 'NR>1 {print \"DROP USER IF EXISTS \\\"\"\$1"\\\"@\\\"\"\$2"\\\";\"}' | mysql"
    run_task "Flushing Privileges" "mysql -e 'FLUSH PRIVILEGES'"
}

remove_users_and_cron() {
    run_task "Killing Panel Users" "pkill -u pterodactyl 2>/dev/null"
    run_task "Deleting Users" "userdel -r pterodactyl 2>/dev/null"
    run_task "Cleaning Crontab" "crontab -l | grep -v 'pterodactyl' | crontab -"
}

clean_docker() {
    run_task "Stopping Docker Containers" "docker stop \\$(docker ps -aq) 2>/dev/null"
    run_task "Removing Docker Containers" "docker rm \\$(docker ps -aq) 2>/dev/null"
    run_task "Removing Docker Images" "docker rmi \\$(docker images -q) 2>/dev/null"
    run_task "Pruning Docker System" "docker system prune -af"
}

system_cleanup() {
    run_task "Apt Update & Upgrade" "apt-get update && apt-get -y upgrade"
    run_task "Apt Deep Clean" "apt-get -y autoremove && apt-get -y autoclean && apt-get clean"
    run_task "Removing Temp Files" "find /tmp /var/tmp -type f -atime +1 -delete"
    run_task "Clearing Journal Logs" "journalctl --rotate && journalctl --vacuum-time=1d"
}

# ================= MAIN =================
main() {
    if [ "$(id -u)" -ne 0 ]; then
        echo -e "${RED}✗ This tool must be run as root!${NC}"
        exit 1
    fi
    display_header
    echo -e "${RED}⚠ This operation will permanently erase panel-related data!${NC}"
    read -p "Continue? (y/N): " -n 1 -r
    echo
    [[ ! $REPLY =~ ^[Yy]$ ]] && exit 1

    remove_pterodactyl_files
    remove_mysql_data
    remove_users_and_cron
    clean_docker
    system_cleanup

    echo -e "\n${GREEN}✅ VPS cleanup completed successfully.${NC}"
    echo -e "${CYAN}Detailed log: ${YELLOW}$LOG_FILE${NC}"
}

main
