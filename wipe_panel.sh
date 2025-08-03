#!/bin/bash

# ================= CONFIGURATION =================
# Personalization
YOUR_NAME="Golden Hosting"

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

# Logger setup
LOG_DIR="/var/log/golden_hosting"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/cleanup_$(date +%Y%m%d_%H%M%S).log"
exec > >(tee -a "$LOG_FILE") 2>&1

# Loading animation
LOADING_CHARS=("⠋" "⠙" "⠹" "⠸" "⠼" "⠴" "⠦" "⠧" "⠇" "⠏")
CHINESE_CHARS=("清" "理" "中" "请" "稍" "等" "片" "刻" "完" "成")

# ================= CORE FUNCTIONS =================
display_header() {
    clear
    echo -e "${PURPLE}╔═══════════════════════════════════════╗"
    echo -e "║     ${YELLOW}GOLDEN HOSTING TOOLKIT v2.3${PURPLE}       ║"
    echo -e "║   ${CYAN}Forensic VPS Cleaner - Hardcore${PURPLE}     ║"
    echo -e "╚═══════════════════════════════════════╝${NC}"
    echo -e "${BLUE}Operator: ${GREEN}$YOUR_NAME${NC}"
    echo -e "${BLUE}Logfile: ${YELLOW}$LOG_FILE${NC}"
    echo -e "${GREEN}Started: $(date)${NC}\n"
}

show_loading() {
    local pid=$1
    local text=$2
    local delay=0.1
    local i=0
    while kill -0 $pid 2>/dev/null; do
        local zh="${CHINESE_CHARS[i % ${#CHINESE_CHARS[@]}]}"
        local lo="${LOADING_CHARS[i % ${#LOADING_CHARS[@]}]}"
        echo -ne "\r$zh $lo ${YELLOW}$text${NC}   "
        sleep $delay
        ((i++))
    done
    echo -ne "\r${GREEN}✓ ${text} completed${NC}            \n"
}

execute_task() {
    local task_name="$1"
    local task_command="$2"
    echo -e "\n${PURPLE}▶ Starting: ${CYAN}$task_name${NC}"
    bash -c "$task_command" &
    local pid=$!
    show_loading $pid "$task_name"
    wait $pid
    return $?
}

# ================= CLEANUP FUNCTIONS =================
analyze_system() {
    echo -e "\n${CYAN}🔍 Running Forensic Analysis...${NC}"
    execute_task "Finding Pterodactyl Files" "find /var/www /etc /opt /srv -type f -iname '*pterodactyl*'"
    execute_task "Checking System Users" "getent passwd | grep -E 'pterodactyl|panel|wings|container'"
    execute_task "Listing Services" "systemctl list-units --type=service | grep -E 'pterodactyl|wings'"
}

remove_panel() {
    echo -e "\n${RED}🧹 Removing Panel Components...${NC}"
    execute_task "Stopping Services" "systemctl stop wings pteroq 2>/dev/null"
    execute_task "Removing Files" "rm -rf /var/www/pterodactyl /etc/pterodactyl /srv/daemon /usr/local/bin/wings"
    execute_task "Disabling Services" "systemctl disable wings pteroq 2>/dev/null"
    execute_task "Cleaning Cronjobs" "crontab -l | grep -v 'pterodactyl' | crontab -"
}

remove_mysql() {
    echo -e "\n${RED}🗑️ Wiping MySQL Data...${NC}"
    if ! command -v mysql >/dev/null; then
        echo -e "${YELLOW}[!] MySQL not found, skipping.${NC}"
        return
    fi
    execute_task "Drop User Accounts" "mysql -e \"SELECT CONCAT('DROP USER IF EXISTS \\\\'', User, '\\\'@\\\'', Host, '\\\';') FROM mysql.user WHERE User NOT IN ('mysql.sys','root','mysql.session','debian-sys-maint')\" | mysql"
    execute_task "Drop Extra Databases" "mysql -e \"SHOW DATABASES\" | grep -Ev 'mysql|information_schema|performance_schema|sys' | xargs -I{} mysql -e 'DROP DATABASE IF EXISTS \`{}\`;'"
}

remove_users() {
    echo -e "\n${RED}👥 Removing Linux Users...${NC}"
    execute_task "Killing Panel Users" "pkill -u pterodactyl 2>/dev/null"
    execute_task "Deleting Users" "userdel -r pterodactyl 2>/dev/null"
}

docker_cleanup() {
    echo -e "\n${RED}🐳 Removing Docker Artifacts...${NC}"
    execute_task "Stopping Docker Containers" "docker stop \$(docker ps -aq) 2>/dev/null"
    execute_task "Removing Containers & Images" "docker system prune -a -f 2>/dev/null"
}

system_optimize() {
    echo -e "\n${GREEN}⚡ Optimizing System...${NC}"
    execute_task "Cleaning APT Cache" "apt-get autoremove -y && apt-get autoclean -y"
    execute_task "Removing Logs" "find /var/log -type f -name '*.log' -delete"
}

# ================= MAIN =================
main() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}[✗] Please run as root.${NC}"
        exit 1
    fi

    display_header
    analyze_system

    echo -e "\n${RED}⚠ Confirm you want to fully wipe panel data (y/N):${NC}"
    read -r CONFIRM
    if [[ "$CONFIRM" != "y" && "$CONFIRM" != "Y" ]]; then
        echo -e "${YELLOW}Aborted.${NC}"
        exit 1
    fi

    remove_panel
    remove_mysql
    remove_users
    docker_cleanup
    system_optimize

    echo -e "\n${GREEN}✅ Cleanup Complete. VPS is now clean.${NC}"
    echo -e "${BLUE}Log: ${YELLOW}$LOG_FILE${NC}"
    echo -e "${CYAN}~ Golden Hosting Toolkit v2.3 ~${NC}"
}

main
