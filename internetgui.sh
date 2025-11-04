#!/data/data/com.termux/files/usr/bin/bash

# ═══════════════════════════════════════════════════
# 🔥 TERMUX HOTSPOT MANAGER v1.0
# ═══════════════════════════════════════════════════
# Credit: senz
# ═══════════════════════════════════════════════════

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m' # No Color
BOLD='\033[1m'

# Config file
CONFIG_DIR="$HOME/.hotspot_manager"
CONFIG_FILE="$CONFIG_DIR/config.conf"
CLIENTS_FILE="$CONFIG_DIR/clients.db"
STATS_FILE="$CONFIG_DIR/stats.log"

# Global variables
ROOT_AVAILABLE=0
MAGISK_AVAILABLE=0

# ═══════════════════════════════════════════════════
# ASCII ART BANNER
# ═══════════════════════════════════════════════════
show_banner() {
    clear
    echo -e "${CYAN}"
    cat << "EOF"
    ╔═══════════════════════════════════════════════════════╗
    ║                                                       ║
    ║   ██╗  ██╗ ██████╗ ████████╗███████╗██████╗  ██████╗ ║
    ║   ██║  ██║██╔═══██╗╚══██╔══╝██╔════╝██╔══██╗██╔═══██╗║
    ║   ███████║██║   ██║   ██║   ███████╗██████╔╝██║   ██║║
    ║   ██╔══██║██║   ██║   ██║   ╚════██║██╔═══╝ ██║   ██║║
    ║   ██║  ██║╚██████╔╝   ██║   ███████║██║     ╚██████╔╝║
    ║   ╚═╝  ╚═╝ ╚═════╝    ╚═╝   ╚══════╝╚═╝      ╚═════╝ ║
    ║                                                       ║
    ║        ███╗   ███╗ █████╗ ███╗   ██╗ █████╗  ██████╗ ║
    ║        ████╗ ████║██╔══██╗████╗  ██║██╔══██╗██╔════╝ ║
    ║        ██╔████╔██║███████║██╔██╗ ██║███████║██║  ███╗║
    ║        ██║╚██╔╝██║██╔══██║██║╚██╗██║██╔══██║██║   ██║║
    ║        ██║ ╚═╝ ██║██║  ██║██║ ╚████║██║  ██║╚██████╔╝║
    ║        ╚═╝     ╚═╝╚═╝  ╚═╝╚═╝  ╚═══╝╚═╝  ╚═╝ ╚═════╝ ║
    ║                                                       ║
    ╚═══════════════════════════════════════════════════════╝
EOF
    echo -e "${NC}"
    echo -e "${PURPLE}${BOLD}              Advanced Hotspot Management Tool${NC}"
    echo -e "${YELLOW}                    Credit: senz${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════════${NC}\n"
}

# ═══════════════════════════════════════════════════
# CHECK ROOT AND MAGISK
# ═══════════════════════════════════════════════════
check_root() {
    echo -e "${YELLOW}[*] Checking root access...${NC}"
    
    # Check for su binary
    if command -v su &> /dev/null; then
        if su -c "id" 2>/dev/null | grep -q "uid=0"; then
            ROOT_AVAILABLE=1
            echo -e "${GREEN}[✓] Root access: ${BOLD}AVAILABLE${NC}"
        else
            echo -e "${RED}[✗] Root access: ${BOLD}NOT AVAILABLE${NC}"
        fi
    else
        echo -e "${RED}[✗] SU binary: ${BOLD}NOT FOUND${NC}"
    fi
    
    # Check for Magisk
    if [ -f "/data/adb/magisk/magisk" ] || [ -d "/data/adb/magisk" ]; then
        MAGISK_AVAILABLE=1
        echo -e "${GREEN}[✓] Magisk: ${BOLD}DETECTED${NC}"
        
        # Get Magisk version if possible
        if command -v magisk &> /dev/null; then
            MAGISK_VER=$(magisk -v 2>/dev/null || echo "Unknown")
            echo -e "${CYAN}[i] Magisk Version: ${MAGISK_VER}${NC}"
        fi
    else
        echo -e "${RED}[✗] Magisk: ${BOLD}NOT DETECTED${NC}"
    fi
    
    echo ""
    sleep 1
}

# ═══════════════════════════════════════════════════
# INSTALL DEPENDENCIES
# ═══════════════════════════════════════════════════
install_dependencies() {
    echo -e "${YELLOW}[*] Checking and installing dependencies...${NC}\n"
    
    # Update package list
    echo -e "${CYAN}[*] Updating package lists...${NC}"
    pkg update -y 2>/dev/null
    
    # Required packages
    PACKAGES=("termux-api" "iproute2" "net-tools" "dnsmasq" "iptables" "wireless-tools" "procps" "grep" "sed" "bc")
    
    for package in "${PACKAGES[@]}"; do
        if ! dpkg -s "$package" &> /dev/null; then
            echo -e "${YELLOW}[*] Installing $package...${NC}"
            pkg install -y "$package" 2>/dev/null
            if [ $? -eq 0 ]; then
                echo -e "${GREEN}[✓] $package installed successfully${NC}"
            else
                echo -e "${RED}[✗] Failed to install $package${NC}"
            fi
        else
            echo -e "${GREEN}[✓] $package already installed${NC}"
        fi
    done
    
    echo ""
    sleep 1
}

# ═══════════════════════════════════════════════════
# INITIALIZE CONFIG
# ═══════════════════════════════════════════════════
init_config() {
    mkdir -p "$CONFIG_DIR"
    
    if [ ! -f "$CONFIG_FILE" ]; then
        cat > "$CONFIG_FILE" << EOF
HOTSPOT_SSID="Termux_Hotspot"
HOTSPOT_PASSWORD="termux123"
HOTSPOT_MAX_CLIENTS=8
HOTSPOT_BAND=2.4GHz
HOTSPOT_SECURITY=WPA2
DEFAULT_SPEED_LIMIT=0
HOTSPOT_INTERFACE=wlan0
EOF
        echo -e "${GREEN}[✓] Configuration file created${NC}"
    fi
    
    touch "$CLIENTS_FILE"
    touch "$STATS_FILE"
}

# ═══════════════════════════════════════════════════
# LOAD CONFIG
# ═══════════════════════════════════════════════════
load_config() {
    if [ -f "$CONFIG_FILE" ]; then
        source "$CONFIG_FILE"
    fi
}

# ═══════════════════════════════════════════════════
# SAVE CONFIG
# ═══════════════════════════════════════════════════
save_config() {
    cat > "$CONFIG_FILE" << EOF
HOTSPOT_SSID="$HOTSPOT_SSID"
HOTSPOT_PASSWORD="$HOTSPOT_PASSWORD"
HOTSPOT_MAX_CLIENTS=$HOTSPOT_MAX_CLIENTS
HOTSPOT_BAND=$HOTSPOT_BAND
HOTSPOT_SECURITY=$HOTSPOT_SECURITY
DEFAULT_SPEED_LIMIT=$DEFAULT_SPEED_LIMIT
HOTSPOT_INTERFACE=$HOTSPOT_INTERFACE
EOF
}

# ═══════════════════════════════════════════════════
# EXECUTE ROOT COMMAND
# ═══════════════════════════════════════════════════
exec_root() {
    if [ $ROOT_AVAILABLE -eq 1 ]; then
        su -c "$1" 2>/dev/null
    else
        echo -e "${RED}[✗] Root access required for this operation${NC}"
        return 1
    fi
}

# ═══════════════════════════════════════════════════
# GET HOTSPOT STATUS
# ═══════════════════════════════════════════════════
get_hotspot_status() {
    if [ $ROOT_AVAILABLE -eq 1 ]; then
        local status=$(exec_root "getprop init.svc.hostapd 2>/dev/null")
        if [ "$status" == "running" ]; then
            echo -e "${GREEN}ENABLED${NC}"
        else
            # Alternative check
            if exec_root "ip link show | grep -q 'ap0\\|wlan0.*UP'"; then
                echo -e "${GREEN}ENABLED${NC}"
            else
                echo -e "${RED}DISABLED${NC}"
            fi
        fi
    else
        echo -e "${YELLOW}UNKNOWN${NC}"
    fi
}

# ═══════════════════════════════════════════════════
# TOGGLE HOTSPOT
# ═══════════════════════════════════════════════════
toggle_hotspot() {
    local action=$1
    
    if [ $ROOT_AVAILABLE -eq 0 ]; then
        echo -e "${RED}[✗] Root access required to toggle hotspot${NC}"
        echo -e "${YELLOW}[!] Please enable hotspot manually via Android settings${NC}"
        read -p "Press Enter to continue..."
        return
    fi
    
    if [ "$action" == "start" ]; then
        echo -e "${YELLOW}[*] Starting hotspot...${NC}"
        
        # Method 1: Using service call
        exec_root "svc wifi enable" 2>/dev/null
        sleep 1
        exec_root "cmd wifi set-wifi-ap-enabled true" 2>/dev/null
        
        # Method 2: Using settings command
        exec_root "settings put global tether_dun_required 0" 2>/dev/null
        exec_root "service call connectivity 33 i32 1" 2>/dev/null
        
        sleep 2
        echo -e "${GREEN}[✓] Hotspot start command sent${NC}"
        
    elif [ "$action" == "stop" ]; then
        echo -e "${YELLOW}[*] Stopping hotspot...${NC}"
        
        exec_root "cmd wifi set-wifi-ap-enabled false" 2>/dev/null
        exec_root "service call connectivity 33 i32 0" 2>/dev/null
        
        sleep 2
        echo -e "${GREEN}[✓] Hotspot stop command sent${NC}"
    fi
    
    read -p "Press Enter to continue..."
}

# ═══════════════════════════════════════════════════
# GET CONNECTED CLIENTS
# ═══════════════════════════════════════════════════
get_connected_clients() {
    if [ $ROOT_AVAILABLE -eq 0 ]; then
        echo "Root required"
        return
    fi
    
    # Try to get ARP table
    exec_root "cat /proc/net/arp" 2>/dev/null | grep -v "00:00:00:00:00:00" | grep -v "HW" | awk '{print $1" "$4}'
}

# ═══════════════════════════════════════════════════
# GET NETWORK STATS
# ═══════════════════════════════════════════════════
get_network_stats() {
    local interface=${1:-wlan0}
    
    if [ -f "/sys/class/net/$interface/statistics/rx_bytes" ]; then
        local rx_bytes=$(cat /sys/class/net/$interface/statistics/rx_bytes 2>/dev/null || echo 0)
        local tx_bytes=$(cat /sys/class/net/$interface/statistics/tx_bytes 2>/dev/null || echo 0)
        
        # Convert to human readable
        local rx_mb=$(echo "scale=2; $rx_bytes / 1048576" | bc 2>/dev/null || echo "0")
        local tx_mb=$(echo "scale=2; $tx_bytes / 1048576" | bc 2>/dev/null || echo "0")
        
        echo "RX: ${rx_mb} MB | TX: ${tx_mb} MB"
    else
        echo "Interface not found"
    fi
}

# ═══════════════════════════════════════════════════
# REALTIME STATS MONITOR
# ═══════════════════════════════════════════════════
realtime_stats() {
    local interface=${HOTSPOT_INTERFACE:-wlan0}
    
    show_banner
    echo -e "${CYAN}${BOLD}═══════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}${BOLD}           REAL-TIME NETWORK STATISTICS${NC}"
    echo -e "${CYAN}${BOLD}═══════════════════════════════════════════════════════${NC}\n"
    echo -e "${YELLOW}[*] Monitoring interface: $interface${NC}"
    echo -e "${YELLOW}[*] Press Ctrl+C to exit${NC}\n"
    
    # Get initial values
    if [ -f "/sys/class/net/$interface/statistics/rx_bytes" ]; then
        local prev_rx=$(cat /sys/class/net/$interface/statistics/rx_bytes 2>/dev/null || echo 0)
        local prev_tx=$(cat /sys/class/net/$interface/statistics/tx_bytes 2>/dev/null || echo 0)
    else
        echo -e "${RED}[✗] Interface $interface not found${NC}"
        read -p "Press Enter to continue..."
        return
    fi
    
    while true; do
        sleep 1
        
        local curr_rx=$(cat /sys/class/net/$interface/statistics/rx_bytes 2>/dev/null || echo 0)
        local curr_tx=$(cat /sys/class/net/$interface/statistics/tx_bytes 2>/dev/null || echo 0)
        
        local rx_rate=$((curr_rx - prev_rx))
        local tx_rate=$((curr_tx - prev_tx))
        
        # Convert to KB/s
        local rx_kbs=$(echo "scale=2; $rx_rate / 1024" | bc 2>/dev/null || echo "0")
        local tx_kbs=$(echo "scale=2; $tx_rate / 1024" | bc 2>/dev/null || echo "0")
        
        # Total in MB
        local total_rx_mb=$(echo "scale=2; $curr_rx / 1048576" | bc 2>/dev/null || echo "0")
        local total_tx_mb=$(echo "scale=2; $curr_tx / 1048576" | bc 2>/dev/null || echo "0")
        
        # Clear and display
        tput cup 8 0
        echo -e "${GREEN}┌─────────────────────────────────────────────────────┐${NC}"
        echo -e "${GREEN}│${NC} ${BOLD}Download Speed:${NC} ${CYAN}${rx_kbs} KB/s${NC}$(printf '%*s' $((37 - ${#rx_kbs})) '')${GREEN}│${NC}"
        echo -e "${GREEN}│${NC} ${BOLD}Upload Speed:${NC}   ${CYAN}${tx_kbs} KB/s${NC}$(printf '%*s' $((37 - ${#tx_kbs})) '')${GREEN}│${NC}"
        echo -e "${GREEN}├─────────────────────────────────────────────────────┤${NC}"
        echo -e "${GREEN}│${NC} ${BOLD}Total Downloaded:${NC} ${PURPLE}${total_rx_mb} MB${NC}$(printf '%*s' $((33 - ${#total_rx_mb})) '')${GREEN}│${NC}"
        echo -e "${GREEN}│${NC} ${BOLD}Total Uploaded:${NC}   ${PURPLE}${total_tx_mb} MB${NC}$(printf '%*s' $((33 - ${#total_tx_mb})) '')${GREEN}│${NC}"
        echo -e "${GREEN}└─────────────────────────────────────────────────────┘${NC}"
        
        # Connected clients
        if [ $ROOT_AVAILABLE -eq 1 ]; then
            echo -e "\n${YELLOW}${BOLD}Connected Clients:${NC}"
            local clients=$(get_connected_clients)
            if [ -n "$clients" ]; then
                echo "$clients" | while read ip mac; do
                    echo -e "  ${CYAN}•${NC} IP: $ip | MAC: $mac"
                done
            else
                echo -e "  ${RED}No clients connected${NC}"
            fi
        fi
        
        prev_rx=$curr_rx
        prev_tx=$curr_tx
    done
}

# ═══════════════════════════════════════════════════
# SET SPEED LIMIT FOR CLIENT
# ═══════════════════════════════════════════════════
set_client_speed_limit() {
    if [ $ROOT_AVAILABLE -eq 0 ]; then
        echo -e "${RED}[✗] Root access required${NC}"
        read -p "Press Enter to continue..."
        return
    fi
    
    show_banner
    echo -e "${CYAN}${BOLD}═══════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}${BOLD}           SET CLIENT SPEED LIMIT${NC}"
    echo -e "${CYAN}${BOLD}═══════════════════════════════════════════════════════${NC}\n"
    
    echo -e "${YELLOW}Connected Clients:${NC}"
    local clients=$(get_connected_clients)
    
    if [ -z "$clients" ]; then
        echo -e "${RED}No clients connected${NC}"
        read -p "Press Enter to continue..."
        return
    fi
    
    echo "$clients" | nl -w2 -s'. '
    echo ""
    
    read -p "Enter client number (or 0 for all): " client_num
    read -p "Enter speed limit in KB/s (0 for unlimited): " speed_limit
    
    if [ "$client_num" == "0" ]; then
        echo -e "${YELLOW}[*] Setting speed limit for all clients...${NC}"
        DEFAULT_SPEED_LIMIT=$speed_limit
        save_config
        
        # Apply to all connected clients
        echo "$clients" | while read ip mac; do
            apply_speed_limit "$ip" "$speed_limit"
        done
    else
        local selected=$(echo "$clients" | sed -n "${client_num}p")
        local ip=$(echo $selected | awk '{print $1}')
        
        if [ -n "$ip" ]; then
            echo -e "${YELLOW}[*] Setting speed limit for $ip...${NC}"
            apply_speed_limit "$ip" "$speed_limit"
            
            # Save to clients database
            sed -i "/^$ip/d" "$CLIENTS_FILE" 2>/dev/null
            echo "$ip $speed_limit" >> "$CLIENTS_FILE"
        fi
    fi
    
    echo -e "${GREEN}[✓] Speed limit applied${NC}"
    read -p "Press Enter to continue..."
}

# ═══════════════════════════════════════════════════
# APPLY SPEED LIMIT
# ═══════════════════════════════════════════════════
apply_speed_limit() {
    local ip=$1
    local limit=$2
    
    if [ "$limit" == "0" ]; then
        # Remove limit
        exec_root "tc qdisc del dev ${HOTSPOT_INTERFACE} root 2>/dev/null"
        exec_root "iptables -D FORWARD -s $ip -j DROP 2>/dev/null"
    else
        # Apply limit using tc (traffic control)
        exec_root "tc qdisc add dev ${HOTSPOT_INTERFACE} root handle 1: htb default 12"
        exec_root "tc class add dev ${HOTSPOT_INTERFACE} parent 1: classid 1:1 htb rate ${limit}kbit"
        exec_root "tc filter add dev ${HOTSPOT_INTERFACE} protocol ip parent 1:0 prio 1 u32 match ip dst $ip flowid 1:1"
    fi
}

# ═══════════════════════════════════════════════════
# HOTSPOT SETTINGS MENU
# ═══════════════════════════════════════════════════
hotspot_settings() {
    while true; do
        show_banner
        load_config
        
        echo -e "${CYAN}${BOLD}═══════════════════════════════════════════════════════${NC}"
        echo -e "${CYAN}${BOLD}              HOTSPOT SETTINGS${NC}"
        echo -e "${CYAN}${BOLD}═══════════════════════════════════════════════════════${NC}\n"
        
        echo -e "${YELLOW}Current Configuration:${NC}"
        echo -e "  ${CYAN}1.${NC} SSID (Name):        ${WHITE}$HOTSPOT_SSID${NC}"
        echo -e "  ${CYAN}2.${NC} Password:           ${WHITE}$(echo $HOTSPOT_PASSWORD | sed 's/./*/g')${NC}"
        echo -e "  ${CYAN}3.${NC} Max Clients:        ${WHITE}$HOTSPOT_MAX_CLIENTS${NC}"
        echo -e "  ${CYAN}4.${NC} Frequency Band:     ${WHITE}$HOTSPOT_BAND${NC}"
        echo -e "  ${CYAN}5.${NC} Security:           ${WHITE}$HOTSPOT_SECURITY${NC}"
        echo -e "  ${CYAN}6.${NC} Interface:          ${WHITE}$HOTSPOT_INTERFACE${NC}"
        echo -e "  ${CYAN}7.${NC} Default Speed Limit: ${WHITE}$DEFAULT_SPEED_LIMIT KB/s${NC}"
        echo ""
        echo -e "  ${CYAN}0.${NC} Back to Main Menu"
        echo ""
        echo -e "${CYAN}═══════════════════════════════════════════════════════${NC}"
        
        read -p "$(echo -e ${GREEN}Choose option: ${NC})" choice
        
        case $choice in
            1)
                read -p "Enter new SSID: " new_ssid
                if [ -n "$new_ssid" ]; then
                    HOTSPOT_SSID="$new_ssid"
                    save_config
                    echo -e "${GREEN}[✓] SSID updated${NC}"
                fi
                ;;
            2)
                read -p "Enter new password (min 8 chars): " new_pass
                if [ ${#new_pass} -ge 8 ]; then
                    HOTSPOT_PASSWORD="$new_pass"
                    save_config
                    echo -e "${GREEN}[✓] Password updated${NC}"
                else
                    echo -e "${RED}[✗] Password must be at least 8 characters${NC}"
                fi
                sleep 1
                ;;
            3)
                read -p "Enter max clients (1-10): " max_clients
                if [ "$max_clients" -ge 1 ] && [ "$max_clients" -le 10 ]; then
                    HOTSPOT_MAX_CLIENTS=$max_clients
                    save_config
                    echo -e "${GREEN}[✓] Max clients updated${NC}"
                else
                    echo -e "${RED}[✗] Invalid number${NC}"
                fi
                sleep 1
                ;;
            4)
                echo "Select band: 1) 2.4GHz  2) 5GHz"
                read -p "Choice: " band_choice
                if [ "$band_choice" == "1" ]; then
                    HOTSPOT_BAND="2.4GHz"
                elif [ "$band_choice" == "2" ]; then
                    HOTSPOT_BAND="5GHz"
                fi
                save_config
                echo -e "${GREEN}[✓] Band updated${NC}"
                sleep 1
                ;;
            5)
                echo "Select security: 1) WPA2  2) WPA3  3) WPA2/WPA3"
                read -p "Choice: " sec_choice
                case $sec_choice in
                    1) HOTSPOT_SECURITY="WPA2" ;;
                    2) HOTSPOT_SECURITY="WPA3" ;;
                    3) HOTSPOT_SECURITY="WPA2/WPA3" ;;
                esac
                save_config
                echo -e "${GREEN}[✓] Security updated${NC}"
                sleep 1
                ;;
            6)
                read -p "Enter interface name (e.g., wlan0, ap0): " new_iface
                if [ -n "$new_iface" ]; then
                    HOTSPOT_INTERFACE="$new_iface"
                    save_config
                    echo -e "${GREEN}[✓] Interface updated${NC}"
                fi
                sleep 1
                ;;
            7)
                read -p "Enter default speed limit in KB/s (0 for unlimited): " speed
                DEFAULT_SPEED_LIMIT=$speed
                save_config
                echo -e "${GREEN}[✓] Default speed limit updated${NC}"
                sleep 1
                ;;
            0)
                break
                ;;
            *)
                echo -e "${RED}Invalid option${NC}"
                sleep 1
                ;;
        esac
    done
}

# ═══════════════════════════════════════════════════
# CLIENT MANAGEMENT
# ═══════════════════════════════════════════════════
client_management() {
    while true; do
        show_banner
        echo -e "${CYAN}${BOLD}═══════════════════════════════════════════════════════${NC}"
        echo -e "${CYAN}${BOLD}              CLIENT MANAGEMENT${NC}"
        echo -e "${CYAN}${BOLD}═══════════════════════════════════════════════════════${NC}\n"
        
        echo -e "${YELLOW}Connected Clients:${NC}"
        
        if [ $ROOT_AVAILABLE -eq 1 ]; then
            local clients=$(get_connected_clients)
            if [ -n "$clients" ]; then
                echo "$clients" | while read ip mac; do
                    # Get speed limit if set
                    local limit=$(grep "^$ip" "$CLIENTS_FILE" 2>/dev/null | awk '{print $2}')
                    [ -z "$limit" ] && limit="unlimited"
                    echo -e "  ${CYAN}•${NC} IP: ${WHITE}$ip${NC} | MAC: ${PURPLE}$mac${NC} | Limit: ${YELLOW}$limit${NC}"
                done
            else
                echo -e "  ${RED}No clients connected${NC}"
            fi
        else
            echo -e "${RED}  Root required to view clients${NC}"
        fi
        
        echo ""
        echo -e "${CYAN}Options:${NC}"
        echo -e "  ${CYAN}1.${NC} Set Speed Limit for Client"
        echo -e "  ${CYAN}2.${NC} Block Client"
        echo -e "  ${CYAN}3.${NC} Unblock Client"
        echo -e "  ${CYAN}4.${NC} View Client Details"
        echo -e "  ${CYAN}5.${NC} Kick Client"
        echo -e "  ${CYAN}0.${NC} Back to Main Menu"
        echo ""
        echo -e "${CYAN}═══════════════════════════════════════════════════════${NC}"
        
        read -p "$(echo -e ${GREEN}Choose option: ${NC})" choice
        
        case $choice in
            1)
                set_client_speed_limit
                ;;
            2)
                block_client
                ;;
            3)
                unblock_client
                ;;
            4)
                view_client_details
                ;;
            5)
                kick_client
                ;;
            0)
                break
                ;;
            *)
                echo -e "${RED}Invalid option${NC}"
                sleep 1
                ;;
        esac
    done
}

# ═══════════════════════════════════════════════════
# BLOCK CLIENT
# ═══════════════════════════════════════════════════
block_client() {
    if [ $ROOT_AVAILABLE -eq 0 ]; then
        echo -e "${RED}[✗] Root access required${NC}"
        read -p "Press Enter to continue..."
        return
    fi
    
    read -p "Enter client IP to block: " client_ip
    
    if [ -n "$client_ip" ]; then
        echo -e "${YELLOW}[*] Blocking $client_ip...${NC}"
        exec_root "iptables -I FORWARD -s $client_ip -j DROP"
        exec_root "iptables -I FORWARD -d $client_ip -j DROP"
        echo -e "${GREEN}[✓] Client blocked${NC}"
    fi
    
    read -p "Press Enter to continue..."
}

# ═══════════════════════════════════════════════════
# UNBLOCK CLIENT
# ═══════════════════════════════════════════════════
unblock_client() {
    if [ $ROOT_AVAILABLE -eq 0 ]; then
        echo -e "${RED}[✗] Root access required${NC}"
        read -p "Press Enter to continue..."
        return
    fi
    
    read -p "Enter client IP to unblock: " client_ip
    
    if [ -n "$client_ip" ]; then
        echo -e "${YELLOW}[*] Unblocking $client_ip...${NC}"
        exec_root "iptables -D FORWARD -s $client_ip -j DROP 2>/dev/null"
        exec_root "iptables -D FORWARD -d $client_ip -j DROP 2>/dev/null"
        echo -e "${GREEN}[✓] Client unblocked${NC}"
    fi
    
    read -p "Press Enter to continue..."
}

# ═══════════════════════════════════════════════════
# KICK CLIENT
# ═══════════════════════════════════════════════════
kick_client() {
    if [ $ROOT_AVAILABLE -eq 0 ]; then
        echo -e "${RED}[✗] Root access required${NC}"
        read -p "Press Enter to continue..."
        return
    fi
    
    read -p "Enter client IP to kick: " client_ip
    
    if [ -n "$client_ip" ]; then
        echo -e "${YELLOW}[*] Kicking $client_ip...${NC}"
        exec_root "arp -d $client_ip 2>/dev/null"
        exec_root "ip neigh del $client_ip dev ${HOTSPOT_INTERFACE} 2>/dev/null"
        echo -e "${GREEN}[✓] Client kicked (may reconnect)${NC}"
    fi
    
    read -p "Press Enter to continue..."
}

# ═══════════════════════════════════════════════════
# VIEW CLIENT DETAILS
# ═══════════════════════════════════════════════════
view_client_details() {
    read -p "Enter client IP: " client_ip
    
    if [ -z "$client_ip" ]; then
        return
    fi
    
    show_banner
    echo -e "${CYAN}${BOLD}═══════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}${BOLD}           CLIENT DETAILS: $client_ip${NC}"
    echo -e "${CYAN}${BOLD}═══════════════════════════════════════════════════════${NC}\n"
    
    # Get MAC address
    local mac=$(get_connected_clients | grep "$client_ip" | awk '{print $2}')
    echo -e "${YELLOW}MAC Address:${NC} $mac"
    
    # Get hostname if available
    if [ $ROOT_AVAILABLE -eq 1 ]; then
        local hostname=$(exec_root "cat /proc/net/arp | grep $client_ip" | awk '{print $6}')
        echo -e "${YELLOW}Hostname:${NC} ${hostname:-Unknown}"
    fi
    
    # Get speed limit
    local limit=$(grep "^$client_ip" "$CLIENTS_FILE" 2>/dev/null | awk '{print $2}')
    echo -e "${YELLOW}Speed Limit:${NC} ${limit:-Unlimited} KB/s"
    
    echo ""
    read -p "Press Enter to continue..."
}

# ═══════════════════════════════════════════════════
# MAIN MENU
# ═══════════════════════════════════════════════════
main_menu() {
    while true; do
        show_banner
        load_config
        
        # Show system status
        echo -e "${CYAN}${BOLD}═══════════════════════════════════════════════════════${NC}"
        echo -e "${CYAN}${BOLD}               SYSTEM STATUS${NC}"
        echo -e "${CYAN}${BOLD}═══════════════════════════════════════════════════════${NC}\n"
        
        echo -e "${YELLOW}Root Status:${NC}    $([ $ROOT_AVAILABLE -eq 1 ] && echo -e ${GREEN}AVAILABLE || echo -e ${RED}NOT AVAILABLE)${NC}"
        echo -e "${YELLOW}Magisk Status:${NC}  $([ $MAGISK_AVAILABLE -eq 1 ] && echo -e ${GREEN}DETECTED || echo -e ${RED}NOT DETECTED)${NC}"
        echo -e "${YELLOW}Hotspot Status:${NC} $(get_hotspot_status)"
        echo -e "${YELLOW}Network Stats:${NC}  $(get_network_stats)"
        
        echo ""
        echo -e "${CYAN}${BOLD}═══════════════════════════════════════════════════════${NC}"
        echo -e "${CYAN}${BOLD}               MAIN MENU${NC}"
        echo -e "${CYAN}${BOLD}═══════════════════════════════════════════════════════${NC}\n"
        
        echo -e "  ${CYAN}1.${NC} ${WHITE}Start Hotspot${NC}"
        echo -e "  ${CYAN}2.${NC} ${WHITE}Stop Hotspot${NC}"
        echo -e "  ${CYAN}3.${NC} ${WHITE}Hotspot Settings${NC}"
        echo -e "  ${CYAN}4.${NC} ${WHITE}Client Management${NC}"
        echo -e "  ${CYAN}5.${NC} ${WHITE}Real-time Statistics${NC}"
        echo -e "  ${CYAN}6.${NC} ${WHITE}View All Clients${NC}"
        echo -e "  ${CYAN}7.${NC} ${WHITE}About & Credits${NC}"
        echo -e "  ${CYAN}0.${NC} ${RED}Exit${NC}"
        echo ""
        echo -e "${CYAN}═══════════════════════════════════════════════════════${NC}"
        
        read -p "$(echo -e ${GREEN}Choose option: ${NC})" choice
        
        case $choice in
            1)
                toggle_hotspot "start"
                ;;
            2)
                toggle_hotspot "stop"
                ;;
            3)
                hotspot_settings
                ;;
            4)
                client_management
                ;;
            5)
                realtime_stats
                ;;
            6)
                show_all_clients
                ;;
            7)
                show_about
                ;;
            0)
                echo -e "\n${CYAN}Thanks for using Hotspot Manager!${NC}"
                echo -e "${YELLOW}Credit: senz${NC}\n"
                exit 0
                ;;
            *)
                echo -e "${RED}Invalid option${NC}"
                sleep 1
                ;;
        esac
    done
}

# ═══════════════════════════════════════════════════
# SHOW ALL CLIENTS
# ═══════════════════════════════════════════════════
show_all_clients() {
    show_banner
    echo -e "${CYAN}${BOLD}═══════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}${BOLD}              CONNECTED CLIENTS${NC}"
    echo -e "${CYAN}${BOLD}═══════════════════════════════════════════════════════${NC}\n"
    
    if [ $ROOT_AVAILABLE -eq 1 ]; then
        local clients=$(get_connected_clients)
        if [ -n "$clients" ]; then
            echo -e "${YELLOW}${BOLD}IP Address${NC}      ${YELLOW}${BOLD}MAC Address${NC}           ${YELLOW}${BOLD}Speed Limit${NC}"
            echo -e "${CYAN}─────────────────────────────────────────────────────${NC}"
            echo "$clients" | while read ip mac; do
                local limit=$(grep "^$ip" "$CLIENTS_FILE" 2>/dev/null | awk '{print $2}')
                [ -z "$limit" ] && limit="∞"
                printf "${WHITE}%-15s${NC} ${PURPLE}%-17s${NC} ${GREEN}%s KB/s${NC}\n" "$ip" "$mac" "$limit"
            done
        else
            echo -e "${RED}No clients connected${NC}"
        fi
    else
        echo -e "${RED}Root access required to view clients${NC}"
    fi
    
    echo ""
    read -p "Press Enter to continue..."
}

# ═══════════════════════════════════════════════════
# ABOUT & CREDITS
# ═══════════════════════════════════════════════════
show_about() {
    show_banner
    echo -e "${CYAN}${BOLD}═══════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}${BOLD}              ABOUT & CREDITS${NC}"
    echo -e "${CYAN}${BOLD}═══════════════════════════════════════════════════════${NC}\n"
    
    echo -e "${WHITE}${BOLD}Hotspot Manager v1.0${NC}"
    echo -e "${YELLOW}Advanced Android Hotspot Management Tool${NC}\n"
    
    echo -e "${CYAN}Features:${NC}"
    echo -e "  ${GREEN}✓${NC} Root & Magisk detection"
    echo -e "  ${GREEN}✓${NC} Hotspot control (Start/Stop)"
    echo -e "  ${GREEN}✓${NC} Real-time network statistics"
    echo -e "  ${GREEN}✓${NC} Client management & monitoring"
    echo -e "  ${GREEN}✓${NC} Per-client speed limiting"
    echo -e "  ${GREEN}✓${NC} Client blocking & kicking"
    echo -e "  ${GREEN}✓${NC} Hotspot configuration"
    echo -e "  ${GREEN}✓${NC} Auto dependency installation"
    
    echo ""
    echo -e "${PURPLE}${BOLD}═══════════════════════════════════════════════════════${NC}"
    echo -e "${PURPLE}${BOLD}              Credit: senz${NC}"
    echo -e "${PURPLE}${BOLD}═══════════════════════════════════════════════════════${NC}\n"
    
    echo -e "${YELLOW}Note:${NC} Some features require root access"
    echo -e "${YELLOW}      Hotspot control may vary by device${NC}\n"
    
    read -p "Press Enter to continue..."
}

# ═══════════════════════════════════════════════════
# MAIN EXECUTION
# ═══════════════════════════════════════════════════
main() {
    # Initial setup
    show_banner
    echo -e "${CYAN}${BOLD}Initializing Hotspot Manager...${NC}\n"
    
    check_root
    install_dependencies
    init_config
    
    echo -e "\n${GREEN}[✓] Initialization complete${NC}"
    sleep 2
    
    # Start main menu
    main_menu
}

# Run main function
main
