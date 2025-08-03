#!/bin/bash

# ================= CONFIGURATION =================
# Personalization
YOUR_NAME="YOUR_NAME_HERE"  # <-- Put your name here

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

# Subtle loading characters
LOADING_CHARS=("⠋" "⠙" "⠹" "⠸" "⠼" "⠴" "⠦" "⠧" "⠇" "⠏")
CHINESE_CHARS=("运" "行" "中" "请" "等" "待" "加" "载" "完" "成")

# ================= CORE FUNCTIONS =================
display_header() {
    clear
    echo -e "${PURPLE}╔═══════════════════════════════════════╗"
    echo -e "║     ${YELLOW}GOLDEN HOSTING TOOLKIT v2.2${PURPLE}       ║"
    echo -e "║   ${CYAN}Forensic VPS Cleaner - Light Ed.${PURPLE}   ║"
    echo -e "╚═══════════════════════════════════════╝${NC}"
    echo -e "${BLUE}Operator: ${GREEN}$YOUR_NAME${NC}"
    echo -e "${BLUE}Logfile: ${YELLOW}$LOG_FILE${NC}"
    echo -e "${GREEN}Started: $(date)${NC}\n"
}

# Subtle loading animation (no full screen takeover)
show_loading() {
    local pid=$1
    local text=$2
    local delay=0.1
    
    while kill -0 $pid 2>/dev/null; do
        for i in "${!LOADING_CHARS[@]}"; do
            echo -ne "\r${CHINESE_CHARS[i]} ${LOADING_CHARS[i]} ${YELLOW}$text${NC}   "
            sleep $delay
            if ! kill -0 $pid 2>/dev/null; then
                break 2
            fi
        done
    done
    echo -ne "\r${GREEN}✓ ${text} completed${NC}            \n"
}

execute_task() {
    local task_name="$1"
    local task_command="$2"
    
    echo -e "\n${PURPLE}▶ Starting: ${CYAN}$task_name${NC}"
    $task_command > /dev/null 2>&1 &
    local pid=$!
    
    show_loading $pid "$task_name"
    
    wait $pid
    return $?
}

# ================= CLEANUP FUNCTIONS =================
analyze_system() {
    echo -e "\n${CYAN}🔍 Running Forensic Analysis...${NC}"
    
    execute_task "Checking Panel Artifacts" "find /var/www /etc -name '*pterodactyl*' -o -name '*panel*' | grep -v 'golden_hosting'"
    execute_task "Checking Wings Services" "systemctl list-units --type=service --no-legend | grep -E 'wings|daemon'"
    execute_task "Checking Database Users" "mysql -e 'SELECT User FROM mysql.user' 2>/dev/null | grep -E 'pterodactyl|panel|wings'"
    execute_task "Checking System Users" "getent passwd | cut -d: -f1 | grep -E 'pterodactyl|panel|wings|container'"
}

remove_panel() {
    echo -e "\n${RED}🧹 Removing Panel Components...${NC}"
    
    execute_task "Stopping Services" "systemctl stop pteroq.service wings 2>/dev/null"
    execute_task "Removing Files" "rm -rf /var/www/pterodactyl /etc/pterodactyl /usr/local/bin/wings"
    execute_task "Cleaning Cron" "crontab -l | grep -v 'pterodactyl' | crontab -"
}

remove_databases() {
    echo -e "\n${RED}🗑️ Cleaning Databases...${NC}"
    
    if ! command -v mysql &>/dev/null; then
        echo -e "${YELLOW}MySQL not installed, skipping${NC}"
        return
    fi

    execute_task "Dropping Databases" "mysql -e 'SHOW DATABASES' | grep -E 'pterodactyl|panel|wings' | xargs -I{} mysql -e 'DROP DATABASE IF EXISTS \`{}\`'"
    execute_task "Removing Users" "mysql -e 'SELECT User FROM mysql.user' | grep -E 'pterodactyl|panel|wings' | xargs -I{} mysql -e 'DROP USER IF EXISTS \"{}\"@\"%\"; DROP USER IF EXISTS \"{}\"@\"localhost\"; FLUSH PRIVILEGES'"
}

remove_users() {
    echo -e "\n${RED}👥 Removing System Users...${NC}"
    
    execute_task "Killing Processes" "for user in $(getent passwd | cut -d: -f1 | grep -E 'pterodactyl|panel|wings|container'); do pkill -9 -u \$user; done"
    execute_task "Deleting Users" "for user in $(getent passwd | cut -d: -f1 | grep -E 'pterodactyl|panel|wings|container'); do userdel -r \$user 2>/dev/null; done"
}

system_optimize() {
    echo -e "\n${GREEN}⚡ Optimizing System...${NC}"
    
    execute_task "Updating Packages" "apt-get update && apt-get -y upgrade"
    execute_task "Cleaning Packages" "apt-get -y autoremove && apt-get -y autoclean"
    execute_task "Cleaning Temp Files" "find /tmp /var/tmp -type f -atime +1 -delete"
}

# ================= MAIN EXECUTION =================
main() {
    # Root check
    if [ "$(id -u)" -ne 0 ]; then
        echo -e "${RED}✗ This tool must be run as root!${NC}"
        exit 1
    fi

    display_header

    # Analysis phase
    analyze_system

    # Confirmation
    echo -e "\n${RED}⚠ WARNING: Destructive operations will follow!${NC}"
    read -p "Are you sure you want to continue? (y/N) " -n 1 -r
    echo
    [[ ! $REPLY =~ ^[Yy]$ ]] && exit 0

    # Cleanup phase
    remove_panel
    remove_databases
    remove_users
    system_optimize

    # Completion
    echo -e "\n${GREEN}✅ Cleanup completed successfully!${NC}"
    echo -e "${CYAN}Detailed log saved to: ${YELLOW}$LOG_FILE${NC}"
    echo -e "\n${PURPLE}Thank you for using Golden Hosting Toolkit${NC}"
    echo -e "${BLUE}Operator: ${GREEN}$YOUR_NAME${NC}\n"
}

main
