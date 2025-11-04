#!/data/data/com.termux/files/usr/bin/bash

# ═══════════════════════════════════════════════════
# TERMUX HOTSPOT MANAGER v2.0
# Dibuat oleh Adam Senzore, Alias Adam Sanjaya <3
# ═══════════════════════════════════════════════════

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m'
BOLD='\033[1m'

# Config file
CONFIG_DIR="$HOME/.hotspot_manager"
CONFIG_FILE="$CONFIG_DIR/config.conf"
CLIENTS_FILE="$CONFIG_DIR/clients.db"
STATS_FILE="$CONFIG_DIR/stats.log"
BLOCKED_FILE="$CONFIG_DIR/blocked.list"

# Global variables
ROOT_AVAILABLE=0
MAGISK_AVAILABLE=0
HOTSPOT_INTERFACE=""
TETHERING_ACTIVE=0

# ═══════════════════════════════════════════════════
# SIMPLE BANNER
# ═══════════════════════════════════════════════════
show_banner() {
    clear
    echo -e "${CYAN}════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}${BOLD}        HOTSPOT MANAGER - TERMUX v2.0${NC}"
    echo -e "${PURPLE}   Dibuat oleh Adam Senzore, Alias Adam Sanjaya <3${NC}"
    echo -e "${CYAN}════════════════════════════════════════════════${NC}\n"
}

# ═══════════════════════════════════════════════════
# CHECK ROOT AND MAGISK
# ═══════════════════════════════════════════════════
check_root() {
    echo -e "${YELLOW}[*] Checking root access...${NC}"
    
    # Try multiple su methods
    if command -v su &> /dev/null; then
        # Test actual root access
        if su -c "id" 2>/dev/null | grep -q "uid=0"; then
            ROOT_AVAILABLE=1
            echo -e "${GREEN}[✓] Root access: AVAILABLE${NC}"
        elif su 0 id 2>/dev/null | grep -q "uid=0"; then
            ROOT_AVAILABLE=1
            echo -e "${GREEN}[✓] Root access: AVAILABLE${NC}"
        else
            echo -e "${RED}[✗] Root access: NOT GRANTED${NC}"
            echo -e "${YELLOW}[!] Please grant superuser permission${NC}"
        fi
    else
        echo -e "${RED}[✗] SU binary: NOT FOUND${NC}"
    fi
    
    # Enhanced Magisk detection
    if [ $ROOT_AVAILABLE -eq 1 ]; then
        # Check multiple Magisk locations
        if su -c "[ -f /data/adb/magisk/magisk ] && echo 1" 2>/dev/null | grep -q "1"; then
            MAGISK_AVAILABLE=1
            echo -e "${GREEN}[✓] Magisk: DETECTED${NC}"
            
            # Try to get version
            local magisk_ver=$(su -c "magisk -v 2>/dev/null" || su -c "magisk -V 2>/dev/null" || echo "Unknown")
            if [ "$magisk_ver" != "Unknown" ]; then
                echo -e "${CYAN}[i] Magisk Version: $magisk_ver${NC}"
            fi
        elif su -c "[ -d /data/adb/magisk ] && echo 1" 2>/dev/null | grep -q "1"; then
            MAGISK_AVAILABLE=1
            echo -e "${GREEN}[✓] Magisk: DETECTED (Directory found)${NC}"
        elif su -c "[ -f /sbin/.magisk/busybox/magisk ] && echo 1" 2>/dev/null | grep -q "1"; then
            MAGISK_AVAILABLE=1
            echo -e "${GREEN}[✓] Magisk: DETECTED${NC}"
        else
            echo -e "${YELLOW}[!] Magisk: NOT DETECTED (Root available via other method)${NC}"
        fi
    fi
    
    echo ""
    sleep 1
}

# ═══════════════════════════════════════════════════
# INSTALL DEPENDENCIES
# ═══════════════════════════════════════════════════
install_dependencies() {
    echo -e "${YELLOW}[*] Checking dependencies...${NC}\n"
    
    # Update package list
    echo -e "${CYAN}[*] Updating packages...${NC}"
    pkg update -y &>/dev/null
    
    # Required packages
    PACKAGES=("termux-api" "iproute2" "net-tools" "procps" "grep" "sed" "bc" "iptables")
    
    for package in "${PACKAGES[@]}"; do
        if ! dpkg -s "$package" &> /dev/null; then
            echo -e "${YELLOW}[*] Installing $package...${NC}"
            pkg install -y "$package" &>/dev/null
            if [ $? -eq 0 ]; then
                echo -e "${GREEN}[✓] $package installed${NC}"
            else
                echo -e "${RED}[✗] Failed to install $package${NC}"
            fi
        else
            echo -e "${GREEN}[✓] $package OK${NC}"
        fi
    done
    
    echo ""
    sleep 1
}

# ═══════════════════════════════════════════════════
# DETECT HOTSPOT/TETHERING INTERFACE
# ═══════════════════════════════════════════════════
detect_hotspot_interface() {
    if [ $ROOT_AVAILABLE -eq 0 ]; then
        HOTSPOT_INTERFACE="wlan0"
        return
    fi
    
    # Check for common tethering interfaces
    local interfaces=$(su -c "ip link show" 2>/dev/null | grep -E "wlan0|ap0|swlan0|softap0|rndis0" | awk -F: '{print $2}' | tr -d ' ')
    
    # Priority order for Realme devices
    for iface in ap0 swlan0 softap0 wlan0 rndis0; do
        if echo "$interfaces" | grep -q "^$iface$"; then
            # Check if interface is UP
            if su -c "ip link show $iface" 2>/dev/null | grep -q "state UP"; then
                HOTSPOT_INTERFACE="$iface"
                TETHERING_ACTIVE=1
                echo -e "${GREEN}[✓] Active hotspot interface: $iface${NC}"
                return
            fi
        fi
    done
    
    # If no active interface, use default
    for iface in ap0 wlan0; do
        if echo "$interfaces" | grep -q "^$iface$"; then
            HOTSPOT_INTERFACE="$iface"
            echo -e "${YELLOW}[!] Detected interface: $iface (not active)${NC}"
            return
        fi
    done
    
    HOTSPOT_INTERFACE="wlan0"
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
DEFAULT_SPEED_LIMIT=0
EOF
    fi
    
    touch "$CLIENTS_FILE"
    touch "$STATS_FILE"
    touch "$BLOCKED_FILE"
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
DEFAULT_SPEED_LIMIT=$DEFAULT_SPEED_LIMIT
EOF
}

# ═══════════════════════════════════════════════════
# EXECUTE ROOT COMMAND
# ═══════════════════════════════════════════════════
exec_root() {
    if [ $ROOT_AVAILABLE -eq 1 ]; then
        su -c "$1" 2>/dev/null
    else
        echo -e "${RED}[✗] Root required${NC}"
        return 1
    fi
}

# ═══════════════════════════════════════════════════
# GET HOTSPOT STATUS
# ═══════════════════════════════════════════════════
get_hotspot_status() {
    if [ $ROOT_AVAILABLE -eq 0 ]; then
        echo -e "${YELLOW}UNKNOWN (No Root)${NC}"
        return
    fi
    
    detect_hotspot_interface
    
    if [ $TETHERING_ACTIVE -eq 1 ]; then
        echo -e "${GREEN}ACTIVE (${HOTSPOT_INTERFACE})${NC}"
    else
        # Check if tethering is on via settings
        local tether_state=$(su -c "dumpsys wifi | grep 'mApState'" 2>/dev/null | grep -oE "[0-9]+" | tail -1)
        if [ "$tether_state" == "13" ] || [ "$tether_state" == "11" ]; then
            echo -e "${GREEN}ENABLED${NC}"
            TETHERING_ACTIVE=1
        else
            echo -e "${RED}DISABLED${NC}"
        fi
    fi
}

# ═══════════════════════════════════════════════════
# TOGGLE HOTSPOT (Realme specific)
# ═══════════════════════════════════════════════════
toggle_hotspot() {
    local action=$1
    
    if [ $ROOT_AVAILABLE -eq 0 ]; then
        echo -e "${RED}[✗] Root access required${NC}"
        echo -e "${YELLOW}[!] Enable hotspot manually via Settings${NC}"
        read -p "Press Enter to continue..."
        return
    fi
    
    if [ "$action" == "start" ]; then
        echo -e "${YELLOW}[*] Starting hotspot...${NC}"
        
        # Enable WiFi first
        su -c "svc wifi enable" 2>/dev/null
        sleep 1
        
        # Try multiple methods for Realme/ColorOS
        su -c "cmd wifi start-softap" 2>/dev/null
        su -c "service call wifi 28 i32 0 i32 1" 2>/dev/null
        su -c "settings put global wifi_ap_state 13" 2>/dev/null
        
        sleep 2
        echo -e "${GREEN}[✓] Hotspot start command sent${NC}"
        echo -e "${YELLOW}[!] If not started, enable manually in Settings${NC}"
        
    elif [ "$action" == "stop" ]; then
        echo -e "${YELLOW}[*] Stopping hotspot...${NC}"
        
        su -c "cmd wifi stop-softap" 2>/dev/null
        su -c "service call wifi 28 i32 0 i32 0" 2>/dev/null
        su -c "settings put global wifi_ap_state 11" 2>/dev/null
        
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
        echo ""
        return
    fi
    
    detect_hotspot_interface
    
    # Get clients from ARP table
    su -c "ip neigh show dev $HOTSPOT_INTERFACE" 2>/dev/null | grep -E "REACHABLE|STALE|DELAY" | awk '{print $1" "$5}' | grep -v "00:00:00:00:00:00"
    
    # Alternative: check ARP cache
    if [ -z "$(su -c "ip neigh show dev $HOTSPOT_INTERFACE" 2>/dev/null)" ]; then
        su -c "cat /proc/net/arp" 2>/dev/null | grep -v "00:00:00:00:00:00" | grep -v "IP" | grep "$HOTSPOT_INTERFACE" | awk '{print $1" "$4}'
    fi
}

# ═══════════════════════════════════════════════════
# GET NETWORK STATS
# ═══════════════════════════════════════════════════
get_network_stats() {
    detect_hotspot_interface
    local interface=$HOTSPOT_INTERFACE
    
    if [ -f "/sys/class/net/$interface/statistics/rx_bytes" ]; then
        local rx_bytes=$(cat /sys/class/net/$interface/statistics/rx_bytes 2>/dev/null || echo 0)
        local tx_bytes=$(cat /sys/class/net/$interface/statistics/tx_bytes 2>/dev/null || echo 0)
        
        local rx_mb=$(echo "scale=2; $rx_bytes / 1048576" | bc 2>/dev/null || echo "0")
        local tx_mb=$(echo "scale=2; $tx_bytes / 1048576" | bc 2>/dev/null || echo "0")
        
        echo "RX: ${rx_mb} MB | TX: ${tx_mb} MB"
    else
        echo "No data"
    fi
}

# ═══════════════════════════════════════════════════
# REALTIME STATS MONITOR
# ═══════════════════════════════════════════════════
realtime_stats() {
    detect_hotspot_interface
    local interface=$HOTSPOT_INTERFACE
    
    show_banner
    echo -e "${CYAN}════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}${BOLD}           REAL-TIME STATISTICS${NC}"
    echo -e "${CYAN}════════════════════════════════════════════════${NC}\n"
    echo -e "${YELLOW}Interface: $interface${NC}"
    echo -e "${YELLOW}Press Ctrl+C to exit${NC}\n"
    
    if [ ! -f "/sys/class/net/$interface/statistics/rx_bytes" ]; then
        echo -e "${RED}[✗] Interface not found or inactive${NC}"
        read -p "Press Enter to continue..."
        return
    fi
    
    local prev_rx=$(cat /sys/class/net/$interface/statistics/rx_bytes 2>/dev/null || echo 0)
    local prev_tx=$(cat /sys/class/net/$interface/statistics/tx_bytes 2>/dev/null || echo 0)
    
    while true; do
        sleep 1
        
        local curr_rx=$(cat /sys/class/net/$interface/statistics/rx_bytes 2>/dev/null || echo 0)
        local curr_tx=$(cat /sys/class/net/$interface/statistics/tx_bytes 2>/dev/null || echo 0)
        
        local rx_rate=$((curr_rx - prev_rx))
        local tx_rate=$((curr_tx - prev_tx))
        
        local rx_kbs=$(echo "scale=2; $rx_rate / 1024" | bc 2>/dev/null || echo "0")
        local tx_kbs=$(echo "scale=2; $tx_rate / 1024" | bc 2>/dev/null || echo "0")
        
        local total_rx_mb=$(echo "scale=2; $curr_rx / 1048576" | bc 2>/dev/null || echo "0")
        local total_tx_mb=$(echo "scale=2; $curr_tx / 1048576" | bc 2>/dev/null || echo "0")
        
        tput cup 6 0
        echo -e "${GREEN}╔════════════════════════════════════════════════╗${NC}"
        echo -e "${GREEN}║${NC} Download Speed:  ${CYAN}${rx_kbs} KB/s${NC}                     "
        echo -e "${GREEN}║${NC} Upload Speed:    ${CYAN}${tx_kbs} KB/s${NC}                     "
        echo -e "${GREEN}╠════════════════════════════════════════════════╣${NC}"
        echo -e "${GREEN}║${NC} Total Download:  ${PURPLE}${total_rx_mb} MB${NC}                "
        echo -e "${GREEN}║${NC} Total Upload:    ${PURPLE}${total_tx_mb} MB${NC}                "
        echo -e "${GREEN}╚════════════════════════════════════════════════╝${NC}"
        
        if [ $ROOT_AVAILABLE -eq 1 ]; then
            echo -e "\n${YELLOW}Connected Clients:${NC}"
            local clients=$(get_connected_clients)
            if [ -n "$clients" ]; then
                echo "$clients" | while read ip mac; do
                    echo -e "  ${CYAN}•${NC} $ip ($mac)"
                done
            else
                echo -e "  ${RED}No clients${NC}"
            fi
        fi
        
        prev_rx=$curr_rx
        prev_tx=$curr_tx
    done
}

# ═══════════════════════════════════════════════════
# APPLY SPEED LIMIT (FIXED - Working version)
# ═══════════════════════════════════════════════════
apply_speed_limit() {
    local ip=$1
    local limit_kb=$2
    
    if [ $ROOT_AVAILABLE -eq 0 ]; then
        echo -e "${RED}[✗] Root required${NC}"
        return 1
    fi
    
    detect_hotspot_interface
    local iface=$HOTSPOT_INTERFACE
    
    if [ "$limit_kb" == "0" ] || [ -z "$limit_kb" ]; then
        # Remove limit
        echo -e "${YELLOW}[*] Removing speed limit for $ip...${NC}"
        su -c "iptables -D FORWARD -s $ip -j DROP 2>/dev/null" 2>/dev/null
        su -c "iptables -D FORWARD -d $ip -j DROP 2>/dev/null" 2>/dev/null
        su -c "tc filter del dev $iface protocol ip parent 1:0 prio 1 2>/dev/null" 2>/dev/null
        echo -e "${GREEN}[✓] Limit removed${NC}"
    else
        # Apply speed limit
        echo -e "${YELLOW}[*] Applying ${limit_kb} KB/s limit to $ip...${NC}"
        
        # Convert KB/s to kbit/s (multiply by 8)
        local limit_kbit=$((limit_kb * 8))
        
        # Initialize tc if not already done
        su -c "tc qdisc show dev $iface | grep -q htb" 2>/dev/null
        if [ $? -ne 0 ]; then
            su -c "tc qdisc add dev $iface root handle 1: htb default 30" 2>/dev/null
            su -c "tc class add dev $iface parent 1: classid 1:1 htb rate 100mbit" 2>/dev/null
        fi
        
        # Generate unique class ID based on last octet of IP
        local class_id="1:$(echo $ip | cut -d. -f4)"
        
        # Remove existing rules for this IP
        su -c "tc class del dev $iface classid $class_id 2>/dev/null" 2>/dev/null
        su -c "tc filter del dev $iface parent 1: protocol ip prio 1 u32 match ip dst $ip 2>/dev/null" 2>/dev/null
        
        # Add new class with speed limit
        su -c "tc class add dev $iface parent 1:1 classid $class_id htb rate ${limit_kbit}kbit ceil ${limit_kbit}kbit" 2>/dev/null
        
        # Add filter to match traffic to this IP
        su -c "tc filter add dev $iface parent 1: protocol ip prio 1 u32 match ip dst $ip flowid $class_id" 2>/dev/null
        
        # Also limit upload from client
        su -c "tc filter add dev $iface parent 1: protocol ip prio 1 u32 match ip src $ip flowid $class_id" 2>/dev/null
        
        if [ $? -eq 0 ]; then
            echo -e "${GREEN}[✓] Speed limit applied successfully${NC}"
        else
            echo -e "${RED}[✗] Failed to apply limit (tc command failed)${NC}"
        fi
    fi
}

# ═══════════════════════════════════════════════════
# SET SPEED LIMIT FOR CLIENTS
# ═══════════════════════════════════════════════════
set_client_speed_limit() {
    if [ $ROOT_AVAILABLE -eq 0 ]; then
        echo -e "${RED}[✗] Root required${NC}"
        read -p "Press Enter..."
        return
    fi
    
    show_banner
    echo -e "${CYAN}════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}${BOLD}         SET CLIENT SPEED LIMIT${NC}"
    echo -e "${CYAN}════════════════════════════════════════════════${NC}\n"
    
    local clients=$(get_connected_clients)
    
    if [ -z "$clients" ]; then
        echo -e "${RED}[✗] No clients connected${NC}"
        read -p "Press Enter..."
        return
    fi
    
    echo -e "${YELLOW}Connected Clients:${NC}\n"
    
    # Store clients in array
    local -a client_list
    local count=1
    
    while IFS= read -r line; do
        client_list[$count]="$line"
        local ip=$(echo "$line" | awk '{print $1}')
        local mac=$(echo "$line" | awk '{print $2}')
        local current_limit=$(grep "^$ip " "$CLIENTS_FILE" 2>/dev/null | awk '{print $2}')
        [ -z "$current_limit" ] && current_limit="unlimited"
        
        printf "${CYAN}%2d.${NC} IP: ${WHITE}%-15s${NC} MAC: ${PURPLE}%-17s${NC} Limit: ${YELLOW}%s${NC}\n" \
            "$count" "$ip" "$mac" "$current_limit"
        
        count=$((count + 1))
    done <<< "$clients"
    
    echo -e "\n${CYAN}0.${NC} All Clients"
    echo ""
    
    read -p "$(echo -e ${GREEN}Select client [0-$((count-1))]: ${NC})" selection
    read -p "$(echo -e ${GREEN}Speed limit in KB/s [0=unlimited]: ${NC})" speed_limit
    
    # Validate input
    if ! [[ "$speed_limit" =~ ^[0-9]+$ ]]; then
        echo -e "${RED}[✗] Invalid speed value${NC}"
        sleep 1
        return
    fi
    
    if [ "$selection" == "0" ]; then
        # Apply to all clients
        echo -e "\n${YELLOW}[*] Applying to all clients...${NC}\n"
        for i in "${!client_list[@]}"; do
            local ip=$(echo "${client_list[$i]}" | awk '{print $1}')
            apply_speed_limit "$ip" "$speed_limit"
            
            # Save to database
            sed -i "/^$ip /d" "$CLIENTS_FILE" 2>/dev/null
            echo "$ip $speed_limit" >> "$CLIENTS_FILE"
        done
        
        DEFAULT_SPEED_LIMIT=$speed_limit
        save_config
        
    elif [ "$selection" -ge 1 ] && [ "$selection" -lt "$count" ]; then
        # Apply to specific client
        local selected_client="${client_list[$selection]}"
        local ip=$(echo "$selected_client" | awk '{print $1}')
        
        echo ""
        apply_speed_limit "$ip" "$speed_limit"
        
        # Save to database
        sed -i "/^$ip /d" "$CLIENTS_FILE" 2>/dev/null
        echo "$ip $speed_limit" >> "$CLIENTS_FILE"
    else
        echo -e "${RED}[✗] Invalid selection${NC}"
    fi
    
    echo ""
    read -p "Press Enter..."
}

# ═══════════════════════════════════════════════════
# BLOCK CLIENT
# ═══════════════════════════════════════════════════
block_client() {
    if [ $ROOT_AVAILABLE -eq 0 ]; then
        echo -e "${RED}[✗] Root required${NC}"
        read -p "Press Enter..."
        return
    fi
    
    show_banner
    echo -e "${CYAN}════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}${BOLD}              BLOCK CLIENT${NC}"
    echo -e "${CYAN}════════════════════════════════════════════════${NC}\n"
    
    local clients=$(get_connected_clients)
    
    if [ -z "$clients" ]; then
        echo -e "${RED}[✗] No clients connected${NC}"
        read -p "Press Enter..."
        return
    fi
    
    echo -e "${YELLOW}Connected Clients:${NC}\n"
    
    local -a client_list
    local count=1
    
    while IFS= read -r line; do
        client_list[$count]="$line"
        local ip=$(echo "$line" | awk '{print $1}')
        local mac=$(echo "$line" | awk '{print $2}')
        printf "${CYAN}%2d.${NC} IP: ${WHITE}%-15s${NC} MAC: ${PURPLE}%s${NC}\n" "$count" "$ip" "$mac"
        count=$((count + 1))
    done <<< "$clients"
    
    echo ""
    read -p "$(echo -e ${GREEN}Select client to block [1-$((count-1))]: ${NC})" selection
    
    if [ "$selection" -ge 1 ] && [ "$selection" -lt "$count" ]; then
        local selected_client="${client_list[$selection]}"
        local ip=$(echo "$selected_client" | awk '{print $1}')
        local mac=$(echo "$selected_client" | awk '{print $2}')
        
        echo -e "\n${YELLOW}[*] Blocking $ip...${NC}"
        
        su -c "iptables -I FORWARD -s $ip -j DROP" 2>/dev/null
        su -c "iptables -I FORWARD -d $ip -j DROP" 2>/dev/null
        
        # Add to blocked list
        echo "$ip $mac" >> "$BLOCKED_FILE"
        
        echo -e "${GREEN}[✓] Client blocked${NC}"
    else
        echo -e "${RED}[✗] Invalid selection${NC}"
    fi
    
    echo ""
    read -p "Press Enter..."
}

# ═══════════════════════════════════════════════════
# UNBLOCK CLIENT
# ═══════════════════════════════════════════════════
unblock_client() {
    if [ $ROOT_AVAILABLE -eq 0 ]; then
        echo -e "${RED}[✗] Root required${NC}"
        read -p "Press Enter..."
        return
    fi
    
    show_banner
    echo -e "${CYAN}════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}${BOLD}            UNBLOCK CLIENT${NC}"
    echo -e "${CYAN}════════════════════════════════════════════════${NC}\n"
    
    if [ ! -s "$BLOCKED_FILE" ]; then
        echo -e "${RED}[✗] No blocked clients${NC}"
        read -p "Press Enter..."
        return
    fi
    
    echo -e "${YELLOW}Blocked Clients:${NC}\n"
    
    local -a blocked_list
    local count=1
    
    while IFS= read -r line; do
        blocked_list[$count]="$line"
        local ip=$(echo "$line" | awk '{print $1}')
        local mac=$(echo "$line" | awk '{print $2}')
        printf "${CYAN}%2d.${NC} IP: ${WHITE}%-15s${NC} MAC: ${PURPLE}%s${NC}\n" "$count" "$ip" "$mac"
        count=$((count + 1))
    done < "$BLOCKED_FILE"
    
    echo ""
    read -p "$(echo -e ${GREEN}Select client to unblock [1-$((count-1))]: ${NC})" selection
    
    if [ "$selection" -ge 1 ] && [ "$selection" -lt "$count" ]; then
        local selected_client="${blocked_list[$selection]}"
        local ip=$(echo "$selected_client" | awk '{print $1}')
        
        echo -e "\n${YELLOW}[*] Unblocking $ip...${NC}"
        
        su -c "iptables -D FORWARD -s $ip -j DROP 2>/dev/null" 2>/dev/null
        su -c "iptables -D FORWARD -d $ip -j DROP 2>/dev/null" 2>/dev/null
        
        # Remove from blocked list
        sed -i "/^$ip /d" "$BLOCKED_FILE" 2>/dev/null
        
        echo -e "${GREEN}[✓] Client unblocked${NC}"
    else
        echo -e "${RED}[✗] Invalid selection${NC}"
    fi
    
    echo ""
    read -p "Press Enter..."
}

# ═══════════════════════════════════════════════════
# KICK CLIENT
# ═══════════════════════════════════════════════════
kick_client() {
    if [ $ROOT_AVAILABLE -eq 0 ]; then
        echo -e "${RED}[✗] Root required${NC}"
        read -p "Press Enter..."
        return
    fi
    
    show_banner
    echo -e "${CYAN}════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}${BOLD}              KICK CLIENT${NC}"
    echo -e "${CYAN}════════════════════════════════════════════════${NC}\n"
    
    local clients=$(get_connected_clients)
    
    if [ -z "$clients" ]; then
        echo -e "${RED}[✗] No clients connected${NC}"
        read -p "Press Enter..."
        return
    fi
    
    echo -e "${YELLOW}Connected Clients:${NC}\n"
    
    local -a client_list
    local count=1
    
    while IFS= read -r line; do
        client_list[$count]="$line"
        local ip=$(echo "$line" | awk '{print $1}')
        local mac=$(echo "$line" | awk '{print $2}')
        printf "${CYAN}%2d.${NC} IP: ${WHITE}%-15s${NC} MAC: ${PURPLE}%s${NC}\n" "$count" "$ip" "$mac"
        count=$((count + 1))
    done <<< "$clients"
    
    echo ""
    read -p "$(echo -e ${GREEN}Select client to kick [1-$((count-1))]: ${NC})" selection
    
    if [ "$selection" -ge 1 ] && [ "$selection" -lt "$count" ]; then
        local selected_client="${client_list[$selection]}"
        local ip=$(echo "$selected_client" | awk '{print $1}')
        
        echo -e "\n${YELLOW}[*] Kicking $ip...${NC}"
        
        detect_hotspot_interface
        su -c "ip neigh del $ip dev $HOTSPOT_INTERFACE 2>/dev/null" 2>/dev/null
        su -c "arp -d $ip 2>/dev/null" 2>/dev/null
        
        echo -e "${GREEN}[✓] Client kicked (may reconnect)${NC}"
    else
        echo -e "${RED}[✗] Invalid selection${NC}"
    fi
    
    echo ""
    read -p "Press Enter..."
}

# ═══════════════════════════════════════════════════
# HOTSPOT SETTINGS
# ═══════════════════════════════════════════════════
hotspot_settings() {
    while true; do
        show_banner
        load_config
        
        echo -e "${CYAN}════════════════════════════════════════════════${NC}"
        echo -e "${CYAN}${BOLD}            HOTSPOT SETTINGS${NC}"
        echo -e "${CYAN}════════════════════════════════════════════════${NC}\n"
        
        echo -e "${YELLOW}Current Settings:${NC}\n"
        echo -e "${CYAN}1.${NC} SSID:              ${WHITE}$HOTSPOT_SSID${NC}"
        echo -e "${CYAN}2.${NC} Password:          ${WHITE}$(echo $HOTSPOT_PASSWORD | sed 's/./*/g')${NC}"
        echo -e "${CYAN}3.${NC} Max Clients:       ${WHITE}$HOTSPOT_MAX_CLIENTS${NC}"
        echo -e "${CYAN}4.${NC} Default Speed:     ${WHITE}$DEFAULT_SPEED_LIMIT KB/s${NC}"
        echo ""
        echo -e "${CYAN}0.${NC} Back"
        echo ""
        echo -e "${CYAN}════════════════════════════════════════════════${NC}"
        
        read -p "$(echo -e ${GREEN}Choose: ${NC})" choice
        
        case $choice in
            1)
                read -p "New SSID: " new_ssid
                if [ -n "$new_ssid" ]; then
                    HOTSPOT_SSID="$new_ssid"
                    save_config
                    echo -e "${GREEN}[✓] Saved${NC}"
                    sleep 1
                fi
                ;;
            2)
                read -p "New password (min 8 chars): " new_pass
                if [ ${#new_pass} -ge 8 ]; then
                    HOTSPOT_PASSWORD="$new_pass"
                    save_config
                    echo -e "${GREEN}[✓] Saved${NC}"
                else
                    echo -e "${RED}[✗] Too short${NC}"
                fi
                sleep 1
                ;;
            3)
                read -p "Max clients [1-10]: " max_clients
                if [ "$max_clients" -ge 1 ] && [ "$max_clients" -le 10 ]; then
                    HOTSPOT_MAX_CLIENTS=$max_clients
                    save_config
                    echo -e "${GREEN}[✓] Saved${NC}"
                else
                    echo -e "${RED}[✗] Invalid${NC}"
                fi
                sleep 1
                ;;
            4)
                read -p "Default speed limit (KB/s, 0=unlimited): " speed
                DEFAULT_SPEED_LIMIT=$speed
                save_config
                echo -e "${GREEN}[✓] Saved${NC}"
                sleep 1
                ;;
            0)
                break
                ;;
        esac
    done
}

# ═══════════════════════════════════════════════════
# CLIENT MANAGEMENT MENU
# ═══════════════════════════════════════════════════
client_management() {
    while true; do
        show_banner
        echo -e "${CYAN}════════════════════════════════════════════════${NC}"
        echo -e "${CYAN}${BOLD}           CLIENT MANAGEMENT${NC}"
        echo -e "${CYAN}════════════════════════════════════════════════${NC}\n"
        
        if [ $ROOT_AVAILABLE -eq 1 ]; then
            local clients=$(get_connected_clients)
            if [ -n "$clients" ]; then
                echo -e "${YELLOW}Connected Clients:${NC}\n"
                while IFS= read -r line; do
                    local ip=$(echo "$line" | awk '{print $1}')
                    local mac=$(echo "$line" | awk '{print $2}')
                    local limit=$(grep "^$ip " "$CLIENTS_FILE" 2>/dev/null | awk '{print $2}')
                    [ -z "$limit" ] && limit="∞"
                    printf "${CYAN}•${NC} ${WHITE}%-15s${NC} ${PURPLE}%-17s${NC} ${YELLOW}%s KB/s${NC}\n" "$ip" "$mac" "$limit"
                done <<< "$clients"
            else
                echo -e "${RED}No clients connected${NC}"
            fi
        else
            echo -e "${RED}Root required${NC}"
        fi
        
        echo ""
        echo -e "${CYAN}════════════════════════════════════════════════${NC}"
        echo -e "${CYAN}1.${NC} Set Speed Limit"
        echo -e "${CYAN}2.${NC} Block Client"
        echo -e "${CYAN}3.${NC} Unblock Client"
        echo -e "${CYAN}4.${NC} Kick Client"
        echo -e "${CYAN}0.${NC} Back"
        echo -e "${CYAN}════════════════════════════════════════════════${NC}"
        
        read -p "$(echo -e ${GREEN}Choose: ${NC})" choice
        
        case $choice in
            1) set_client_speed_limit ;;
            2) block_client ;;
            3) unblock_client ;;
            4) kick_client ;;
            0) break ;;
        esac
    done
}

# ═══════════════════════════════════════════════════
# MAIN MENU
# ═══════════════════════════════════════════════════
main_menu() {
    while true; do
        show_banner
        load_config
        detect_hotspot_interface
        
        echo -e "${CYAN}════════════════════════════════════════════════${NC}"
        echo -e "${CYAN}${BOLD}              SYSTEM STATUS${NC}"
        echo -e "${CYAN}════════════════════════════════════════════════${NC}\n"
        
        echo -e "${YELLOW}Root:${NC}     $([ $ROOT_AVAILABLE -eq 1 ] && echo -e ${GREEN}Available || echo -e ${RED}No)${NC}"
        echo -e "${YELLOW}Magisk:${NC}   $([ $MAGISK_AVAILABLE -eq 1 ] && echo -e ${GREEN}Detected || echo -e ${RED}No)${NC}"
        echo -e "${YELLOW}Hotspot:${NC}  $(get_hotspot_status)"
        echo -e "${YELLOW}Network:${NC}  $(get_network_stats)"
        
        echo ""
        echo -e "${CYAN}════════════════════════════════════════════════${NC}"
        echo -e "${CYAN}${BOLD}               MAIN MENU${NC}"
        echo -e "${CYAN}════════════════════════════════════════════════${NC}\n"
        
        echo -e "${CYAN}1.${NC} Start Hotspot"
        echo -e "${CYAN}2.${NC} Stop Hotspot"
        echo -e "${CYAN}3.${NC} Hotspot Settings"
        echo -e "${CYAN}4.${NC} Client Management"
        echo -e "${CYAN}5.${NC} Real-time Statistics"
        echo -e "${CYAN}6.${NC} About"
        echo -e "${CYAN}0.${NC} Exit"
        echo ""
        echo -e "${CYAN}════════════════════════════════════════════════${NC}"
        
        read -p "$(echo -e ${GREEN}Choose: ${NC})" choice
        
        case $choice in
            1) toggle_hotspot "start" ;;
            2) toggle_hotspot "stop" ;;
            3) hotspot_settings ;;
            4) client_management ;;
            5) realtime_stats ;;
            6) show_about ;;
            0)
                echo -e "\n${CYAN}Terima kasih!${NC}"
                echo -e "${PURPLE}Dibuat oleh Adam Senzore, Alias Adam Sanjaya <3${NC}\n"
                exit 0
                ;;
        esac
    done
}

# ═══════════════════════════════════════════════════
# ABOUT
# ═══════════════════════════════════════════════════
show_about() {
    show_banner
    echo -e "${CYAN}════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}${BOLD}                 ABOUT${NC}"
    echo -e "${CYAN}════════════════════════════════════════════════${NC}\n"
    
    echo -e "${WHITE}${BOLD}Hotspot Manager v2.0${NC}"
    echo -e "${YELLOW}Advanced Tethering Management for Android${NC}\n"
    
    echo -e "${CYAN}Features:${NC}"
    echo -e "${GREEN}✓${NC} Root & Magisk detection"
    echo -e "${GREEN}✓${NC} Hotspot control"
    echo -e "${GREEN}✓${NC} Real-time statistics"
    echo -e "${GREEN}✓${NC} Per-client speed limiting (Working)"
    echo -e "${GREEN}✓${NC} Client blocking/kicking"
    echo -e "${GREEN}✓${NC} Realme/ColorOS optimized"
    
    echo ""
    echo -e "${PURPLE}════════════════════════════════════════════════${NC}"
    echo -e "${PURPLE}${BOLD}  Dibuat oleh Adam Senzore, Alias Adam Sanjaya <3${NC}"
    echo -e "${PURPLE}════════════════════════════════════════════════${NC}\n"
    
    echo -e "${YELLOW}Note: Root access required for most features${NC}\n"
    
    read -p "Press Enter..."
}

# ═══════════════════════════════════════════════════
# MAIN EXECUTION
# ═══════════════════════════════════════════════════
main() {
    show_banner
    echo -e "${CYAN}Initializing...${NC}\n"
    
    check_root
    install_dependencies
    init_config
    
    echo -e "\n${GREEN}[✓] Ready${NC}"
    sleep 2
    
    main_menu
}

# Run
main
