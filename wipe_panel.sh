#!/bin/bash

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

# Matrix effect characters
MATRIX_CHARS=("人" "之" "初" "性" "本" "善" "性" "相" "近" "习" "相" "远" "苟" "不" "教" "性" "乃" "迁" "教" "之" "道" "贵" "以" "专" "零" "壹" "贰" "叁" "肆" "伍" "陆" "柒" "捌" "玖" "拾")

# Forensic analysis patterns
PANEL_PATTERNS=("/var/www/pterodactyl" "/etc/pterodactyl" "pteroq.service")
WINGS_PATTERNS=("/usr/local/bin/wings" "/etc/systemd/system/wings.service" "/var/lib/pterodactyl")
DB_PATTERNS=("pterodactyl" "panel" "wings" "sftp" "daemon")
USER_PATTERNS=("^pterodactyl" "^panel" "^wings" "^container")

# Header display
display_header() {
    clear
    echo -e "${PURPLE}╔═══════════════════════════════════════╗"
    echo -e "║     ${YELLOW}GOLDEN HOSTING TOOLKIT v2.1${PURPLE}       ║"
    echo -e "║   ${CYAN}Forensic VPS Analysis & Cleanup${PURPLE}    ║"
    echo -e "╚═══════════════════════════════════════╝${NC}"
    echo -e "${BLUE}Logging to: ${YELLOW}${LOG_FILE}${NC}"
    echo -e "${GREEN}Started: $(date)${NC}\n"
    echo -e "${RED}WARNING: This tool will perform destructive operations!${NC}"
    echo -e "${YELLOW}Ensure you have backups before proceeding.${NC}\n"
}

# Matrix animation
matrix_effect() {
    local duration=${1:-2}
    echo -ne "\033[2J\033[3J\033[H"
    
    for ((i=0; i<duration*10; i++)); do
        cols=$(tput cols)
        lines=$(tput lines)
        count=$((cols * lines / 8))
        
        for ((j=0; j<count; j++)); do
            x=$((RANDOM % cols))
            y=$((RANDOM % lines))
            char=${MATRIX_CHARS[$((RANDOM % ${#MATRIX_CHARS[@]}))]}
            color=$((30 + RANDOM % 8))
            
            echo -ne "\033[${y};${x}H\033[${color}m${char}\033[0m"
        done
        sleep 0.1
    done
    echo -ne "\033[2J\033[3J\033[H"
}

# Forensic analysis functions
analyze_system() {
    echo -e "\n${PURPLE}=== FORENSIC ANALYSIS REPORT ===${NC}"
    
    # Panel detection
    echo -e "\n${CYAN}[+] Pterodactyl Panel Artifacts:${NC}"
    local panel_found=0
    for pattern in "${PANEL_PATTERNS[@]}"; do
        if [ -e "$pattern" ]; then
            echo -e "${RED}Found: ${YELLOW}$pattern${NC}"
            panel_found=1
        fi
    done
    [ $panel_found -eq 0 ] && echo -e "${GREEN}No panel artifacts detected${NC}"
    
    # Wings detection
    echo -e "\n${CYAN}[+] Wings Daemon Artifacts:${NC}"
    local wings_found=0
    for pattern in "${WINGS_PATTERNS[@]}"; do
        if [ -e "$pattern" ]; then
            echo -e "${RED}Found: ${YELLOW}$pattern${NC}"
            wings_found=1
        fi
    done
    [ $wings_found -eq 0 ] && echo -e "${GREEN}No wings artifacts detected${NC}"
    
    # Database analysis
    echo -e "\n${CYAN}[+] Database Analysis:${NC}"
    analyze_databases
    
    # User analysis
    echo -e "\n${CYAN}[+] User Account Analysis:${NC}"
    analyze_users
    
    # Service analysis
    echo -e "\n${CYAN}[+] Service Analysis:${NC}"
    analyze_services
    
    # Docker analysis
    echo -e "\n${CYAN}[+] Docker Container Analysis:${NC}"
    analyze_docker
}

analyze_databases() {
    if ! command -v mysql &>/dev/null; then
        echo -e "${YELLOW}MySQL not installed, skipping database analysis${NC}"
        return
    fi
    
    local system_dbs=("information_schema" "mysql" "performance_schema" "sys")
    local all_dbs=$(mysql -e "SHOW DATABASES;" 2>/dev/null | grep -v "Database")
    local suspicious_dbs=()
    
    for db in $all_dbs; do
        local is_system=0
        for system_db in "${system_dbs[@]}"; do
            [ "$db" = "$system_db" ] && is_system=1
        done
        
        if [ $is_system -eq 0 ]; then
            for pattern in "${DB_PATTERNS[@]}"; do
                if [[ "$db" =~ $pattern ]]; then
                    suspicious_dbs+=("$db")
                    echo -e "${RED}Suspicious DB: ${YELLOW}$db${NC}"
                    echo -e "  Size: $(mysql -e "SELECT ROUND(SUM(data_length + index_length) / 1024 / 1024, 2) MB FROM information_schema.TABLES WHERE table_schema = '$db'" 2>/dev/null | grep -v "MB") MB"
                    echo -e "  Tables: $(mysql -e "SELECT COUNT(*) FROM information_schema.TABLES WHERE table_schema = '$db'" 2>/dev/null | grep -v "COUNT")"
                    break
                fi
            done
        fi
    done
    
    [ ${#suspicious_dbs[@]} -eq 0 ] && echo -e "${GREEN}No suspicious databases detected${NC}"
}

analyze_users() {
    local suspicious_users=()
    local all_users=$(getent passwd | cut -d: -f1)
    
    for user in $all_users; do
        for pattern in "${USER_PATTERNS[@]}"; do
            if [[ "$user" =~ $pattern ]]; then
                suspicious_users+=("$user")
                echo -e "${RED}Suspicious user: ${YELLOW}$user${NC}"
                echo -e "  UID: $(id -u "$user" 2>/dev/null)"
                echo -e "  Home: $(getent passwd "$user" | cut -d: -f6)"
                echo -e "  Shell: $(getent passwd "$user" | cut -d: -f7)"
                echo -e "  Last login: $(last -n 1 "$user" 2>/dev/null | head -n 1 | awk '{print $4" "$5" "$6" "$7}')"
                break
            fi
        done
    done
    
    [ ${#suspicious_users[@]} -eq 0 ] && echo -e "${GREEN}No suspicious users detected${NC}"
}

analyze_services() {
    echo -e "\n${CYAN}Systemd Services:${NC}"
    local suspicious_services=()
    local all_services=$(systemctl list-units --type=service --no-legend 2>/dev/null | awk '{print $1}')
    
    for service in $all_services; do
        for pattern in "${PANEL_PATTERNS[@]}" "${WINGS_PATTERNS[@]}"; do
            if [[ "$service" =~ $pattern ]]; then
                suspicious_services+=("$service")
                echo -e "${RED}Suspicious service: ${YELLOW}$service${NC}"
                echo -e "  Status: $(systemctl is-active "$service")"
                echo -e "  Enabled: $(systemctl is-enabled "$service")"
                break
            fi
        done
    done
    
    [ ${#suspicious_services[@]} -eq 0 ] && echo -e "${GREEN}No suspicious services detected${NC}"
}

analyze_docker() {
    if ! command -v docker &>/dev/null; then
        echo -e "${YELLOW}Docker not installed, skipping analysis${NC}"
        return
    fi
    
    echo -e "\n${CYAN}Running Containers:${NC}"
    local running_containers=$(docker ps --format "{{.Names}}" 2>/dev/null)
    if [ -z "$running_containers" ]; then
        echo -e "${GREEN}No running containers${NC}"
    else
        echo -e "${YELLOW}$running_containers${NC}"
    fi
    
    echo -e "\n${CYAN}All Containers:${NC}"
    local all_containers=$(docker ps -a --format "{{.Names}}" 2>/dev/null)
    if [ -z "$all_containers" ]; then
        echo -e "${GREEN}No containers found${NC}"
    else
        echo -e "${YELLOW}$all_containers${NC}"
    fi
    
    echo -e "\n${CYAN}Container Networks:${NC}"
    local networks=$(docker network ls --format "{{.Name}}" 2>/dev/null)
    if [ -z "$networks" ]; then
        echo -e "${GREEN}No docker networks${NC}"
    else
        echo -e "${YELLOW}$networks${NC}"
    fi
}

# Cleanup functions
cleanup_panel() {
    echo -e "\n${RED}=== PANEL CLEANUP ===${NC}"
    
    # Stop and disable services
    for service in $(systemctl list-units --type=service --no-legend | grep -E 'pteroq|pterodactyl' | awk '{print $1}'); do
        echo -e "${YELLOW}Stopping service: $service${NC}"
        systemctl stop "$service"
        systemctl disable "$service"
        systemctl reset-failed "$service"
    done
    
    # Remove files
    for pattern in "${PANEL_PATTERNS[@]}"; do
        if [ -e "$pattern" ]; then
            echo -e "${RED}Removing: $pattern${NC}"
            rm -rf "$pattern"
        fi
    done
    
    # Remove cron jobs
    echo -e "${YELLOW}Cleaning up cron jobs...${NC}"
    crontab -l | grep -v "pterodactyl" | crontab -
    
    # Remove nginx configs
    echo -e "${YELLOW}Removing nginx configurations...${NC}"
    rm -f /etc/nginx/sites-*/pterodactyl*
    rm -f /etc/nginx/conf.d/pterodactyl*
    nginx -t && systemctl reload nginx
}

cleanup_wings() {
    echo -e "\n${RED}=== WINGS CLEANUP ===${NC}"
    
    # Stop and disable services
    for service in $(systemctl list-units --type=service --no-legend | grep -E 'wings|daemon' | awk '{print $1}'); do
        echo -e "${YELLOW}Stopping service: $service${NC}"
        systemctl stop "$service"
        systemctl disable "$service"
        systemctl reset-failed "$service"
    done
    
    # Remove files
    for pattern in "${WINGS_PATTERNS[@]}"; do
        if [ -e "$pattern" ]; then
            echo -e "${RED}Removing: $pattern${NC}"
            rm -rf "$pattern"
        fi
    done
    
    # Cleanup docker
    if command -v docker &>/dev/null; then
        echo -e "${YELLOW}Cleaning up Docker containers...${NC}"
        docker stop $(docker ps -aq) 2>/dev/null
        docker rm $(docker ps -aq) 2>/dev/null
        docker network prune -f
        docker volume prune -f
    fi
}

cleanup_databases() {
    echo -e "\n${RED}=== DATABASE CLEANUP ===${NC}"
    
    if ! command -v mysql &>/dev/null; then
        echo -e "${YELLOW}MySQL not installed, skipping database cleanup${NC}"
        return
    fi
    
    local system_dbs=("information_schema" "mysql" "performance_schema" "sys")
    local all_dbs=$(mysql -e "SHOW DATABASES;" 2>/dev/null | grep -v "Database")
    
    for db in $all_dbs; do
        local is_system=0
        for system_db in "${system_dbs[@]}"; do
            [ "$db" = "$system_db" ] && is_system=1
        done
        
        if [ $is_system -eq 0 ]; then
            for pattern in "${DB_PATTERNS[@]}"; do
                if [[ "$db" =~ $pattern ]]; then
                    echo -e "${RED}Dropping database: $db${NC}"
                    mysql -e "DROP DATABASE IF EXISTS \`$db\`;"
                    break
                fi
            done
        fi
    done
    
    # Cleanup users
    echo -e "\n${YELLOW}Cleaning up database users...${NC}"
    local all_users=$(mysql -e "SELECT User FROM mysql.user;" 2>/dev/null | grep -v "User")
    
    for user in $all_users; do
        for pattern in "${DB_PATTERNS[@]}"; do
            if [[ "$user" =~ $pattern ]]; then
                echo -e "${RED}Dropping user: $user${NC}"
                mysql -e "DROP USER IF EXISTS '$user'@'%';"
                mysql -e "DROP USER IF EXISTS '$user'@'localhost';"
                break
            fi
        done
    done
    
    mysql -e "FLUSH PRIVILEGES;"
}

cleanup_users() {
    echo -e "\n${RED}=== USER CLEANUP ===${NC}"
    
    local all_users=$(getent passwd | cut -d: -f1)
    
    for user in $all_users; do
        for pattern in "${USER_PATTERNS[@]}"; do
            if [[ "$user" =~ $pattern ]]; then
                echo -e "${RED}Removing user: $user${NC}"
                
                # Kill processes
                pkill -9 -u "$user"
                
                # Remove user
                userdel -r "$user" 2>/dev/null
                
                # Remove from sudoers
                sed -i "/^$user/d" /etc/sudoers 2>/dev/null
                sed -i "/^$user/d" /etc/sudoers.d/* 2>/dev/null
                
                break
            fi
        done
    done
}

system_optimization() {
    echo -e "\n${GREEN}=== SYSTEM OPTIMIZATION ===${NC}"
    
    # Update system
    echo -e "${YELLOW}Updating system packages...${NC}"
    apt-get update
    apt-get -y upgrade
    apt-get -y dist-upgrade
    
    # Cleanup packages
    echo -e "${YELLOW}Cleaning up packages...${NC}"
    apt-get -y autoremove
    apt-get -y autoclean
    apt-get -y clean
    
    # Cleanup temp files
    echo -e "${YELLOW}Cleaning up temporary files...${NC}"
    find /tmp -type f -atime +1 -delete
    find /var/tmp -type f -atime +1 -delete
    
    # Cleanup logs
    echo -e "${YELLOW}Rotating logs...${NC}"
    logrotate -f /etc/logrotate.conf
    journalctl --rotate
    journalctl --vacuum-time=1d
}

# Main execution
main() {
    # Root check
    if [ "$(id -u)" -ne 0 ]; then
        echo -e "${RED}This tool must be run as root!${NC}"
        exit 1
    fi
    
    display_header
    matrix_effect 2
    
    # Forensic analysis
    analyze_system
    
    # Confirmation
    echo -e "\n${RED}=== WARNING ===${NC}"
    echo -e "${YELLOW}This will perform destructive operations!${NC}"
    read -p "Are you sure you want to continue? (y/N) " -n 1 -r
    echo
    [[ ! $REPLY =~ ^[Yy]$ ]] && exit 0
    
    # Perform cleanup
    cleanup_panel
    cleanup_wings
    cleanup_databases
    cleanup_users
    system_optimization
    
    # Final report
    matrix_effect 1
    echo -e "\n${GREEN}=== CLEANUP COMPLETED SUCCESSFULLY ===${NC}"
    echo -e "${CYAN}Detailed log saved to: ${YELLOW}$LOG_FILE${NC}"
    echo -e "\n${PURPLE}Consider rebooting your system to complete the cleanup.${NC}"
}

main
