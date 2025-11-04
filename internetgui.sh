#!/data/data/com.termux/files/usr/bin/bash

# ═══════════════════════════════════════════════════
# TERMUX HOTSPOT MANAGER v2.1
# Dibuat oleh Senzore, Alias Adam Sanjaya <3
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
    echo -e "${CYAN}${BOLD}        HOTSPOT MANAGER - TERMUX v2.1${NC}"
    echo -e "${PURPLE}      Dibuat oleh Senzore, Alias Adam Sanjaya <3${NC}"
    echo -e "${CYAN}════════════════════════════════════════════════${NC}\n"
}

# ═══════════════════════════════════════════════════
# CHECK ROOT AND MAGISK
# ═══════════════════════════════════════════════════
check_root() {
    echo -e "${YELLOW}[*] Checking root access...${NC}"
    
    if command -v su &> /dev/null; then
        if su -c "id" 2>/dev/null | grep -q "uid=0"; then
            ROOT_AVAILABLE=1
            echo -e "${GREEN}[✓] Root access: AVAILABLE${NC}"
        else
            echo -e "${RED}[✗] Root access: NOT GRANTED${NC}"
            echo -e "${YELLOW}[!] Please grant superuser permission${NC}"
        fi
    else
        echo -e "${RED}[✗] SU binary: NOT FOUND${NC}"
    fi
    
    if [ $ROOT_AVAILABLE -eq 1 ]; then
        if su -c "[ -f /data/adb/magisk/magisk ] && echo 1" 2>/dev/null | grep -q "1"; then
            MAGISK_AVAILABLE=1
            echo -e "${GREEN}[✓] Magisk: DETECTED${NC}"
        elif su -c "[ -d /data/adb/magisk ] && echo 1" 2>/dev/null | grep -q "1"; then
            MAGISK_AVAILABLE=1
            echo -e "${GREEN}[✓] Magisk: DETECTED${NC}"
        else
            echo -e "${YELLOW}[!] Magisk: NOT DETECTED${NC}"
        fi
    fi
    
    echo ""
    sleep 1
}

# ═══════════════════════════════════════════════════
# INSTALL DEPENDENCIES (Non-blocking)
# ═══════════════════════════════════════════════════
install_dependencies() {
    echo -e "${YELLOW}[*] Checking dependencies...${NC}\n"
    
    echo -e "${CYAN}[*] Updating packages...${NC}"
    pkg update -y 2>/dev/null
    
    PACKAGES=("termux-api" "iproute2" "net-tools" "grep" "sed" "bc")
    
    for package in "${PACKAGES[@]}"; do
        if ! dpkg -s "$package" &> /dev/null; then
            echo -e "${YELLOW}[*] Installing $package...${NC}"
            pkg install -y "$package" 2>/dev/null
            if [ $? -eq 0 ]; then
                echo -e "${GREEN}[✓] $package installed${NC}"
            else
                echo -e "${YELLOW}[!] $package failed (optional)${NC}"
            fi
        else
            echo -e "${GREEN}[✓] $package OK${NC}"
        fi
    done
    
    echo ""
    sleep 1
}

# ═══════════════════════════════════════════════════
# DETECT HOTSPOT INTERFACE (Passive Detection)
# ═══════════════════════════════════════════════════
detect_hotspot_interface() {
    if [ $ROOT_AVAILABLE -eq 0 ]; then
        HOTSPOT_INTERFACE="wlan0"
        return
    fi
    
    local interfaces=$(su -c "ip link show" 2>/dev/null | grep -E "wlan0|ap0|swlan0|softap0" | awk -F: '{print $2}' | tr -d ' ')
    
    for iface in ap0 swlan0 softap0 wlan0; do
        if echo "$interfaces" | grep -q "^$iface$"; then
            if su -c "ip link show $iface" 2>/dev/null | grep -q "state UP"; then
                HOTSPOT_INTERFACE="$iface"
                TETHERING_ACTIVE=1
                return
            fi
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
DEFAULT_SPEED_LIMIT=0
AUTO_BLOCK_UNKNOWN=0
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
DEFAULT_SPEED_LIMIT=$DEFAULT_SPEED_LIMIT
AUTO_BLOCK_UNKNOWN=$AUTO_BLOCK_UNKNOWN
EOF
}

# ═══════════════════════════════════════════════════
# GET HOTSPOT STATUS
# ═══════════════════════════════════════════════════
get_hotspot_status() {
    if [ $ROOT_AVAILABLE -eq 0 ]; then
        echo -e "${YELLOW}UNKNOWN${NC}"
        return
    fi
    
    detect_hotspot_interface
    
    if [ $TETHERING_ACTIVE -eq 1 ]; then
        echo -e "${GREEN}ACTIVE (${HOTSPOT_INTERFACE})${NC}"
    else
        echo -e "${RED}INACTIVE${NC}"
    fi
}

# ═══════════════════════════════════════════════════
# GET CLIENT HOSTNAME
# ═══════════════════════════════════════════════════
get_client_hostname() {
    local ip=$1
    
    if [ $ROOT_AVAILABLE -eq 0 ]; then
        echo "Unknown"
        return
    fi
    
    # Try DHCP leases first (most reliable)
    local hostname=$(su -c "cat /data/misc/dhcp/dnsmasq.leases 2>/dev/null" | grep "$ip" | awk '{print $4}')
    
    # Try alternative DHCP location
    if [ -z "$hostname" ] || [ "$hostname" == "*" ]; then
        hostname=$(su -c "cat /data/vendor/wifi/hostapd/hostapd.leases 2>/dev/null" | grep "$ip" | awk '{print $4}')
    fi
    
    # Try ARP cache hostname
    if [ -z "$hostname" ] || [ "$hostname" == "*" ]; then
        hostname=$(su -c "cat /proc/net/arp" 2>/dev/null | grep "$ip" | awk '{print $6}')
    fi
    
    # Clean up and validate
    hostname=$(echo "$hostname" | tr -d '\n\r' | sed 's/[^a-zA-Z0-9._-]//g')
    
    if [ -z "$hostname" ] || [ "$hostname" == "*" ] || [ "$hostname" == "00:00:00:00:00:00" ]; then
        echo "Unknown Device"
    else
        echo "$hostname"
    fi
}

# ═══════════════════════════════════════════════════
# GET CONNECTED CLIENTS (IPv4 only with hostnames)
# ═══════════════════════════════════════════════════
get_connected_clients() {
    if [ $ROOT_AVAILABLE -eq 0 ]; then
        echo ""
        return
    fi
    
    detect_hotspot_interface
    
    # Get clients and filter IPv4 only
    su -c "ip neigh show dev $HOTSPOT_INTERFACE" 2>/dev/null | \
        grep -E "REACHABLE|STALE|DELAY" | \
        grep -v "00:00:00:00:00:00" | \
        grep -v ":" | \
        awk '{print $1" "$5}' | \
        while read ip mac; do
            # Filter out IPv6 (contains multiple colons in MAC or IP)
            if [[ ! "$ip" =~ .*:.* ]]; then
                echo "$ip $mac"
            fi
        done
    
    # Alternative ARP check for IPv4 only
    if [ -z "$(su -c "ip neigh show dev $HOTSPOT_INTERFACE" 2>/dev/null)" ]; then
        su -c "cat /proc/net/arp" 2>/dev/null | \
            grep -v "00:00:00:00:00:00" | \
            grep -v "IP address" | \
            grep "$HOTSPOT_INTERFACE" | \
            awk '{print $1" "$4}' | \
            grep -v ":" # Filter IPv6
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
        echo -e "${YELLOW}[!] Please enable hotspot from Android Settings${NC}"
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
            echo -e "\n${YELLOW}Connected Clients (IPv4):${NC}"
            local clients=$(get_connected_clients)
            if [ -n "$clients" ]; then
                echo "$clients" | while read ip mac; do
                    local hostname=$(get_client_hostname "$ip")
                    printf "  ${CYAN}•${NC} ${WHITE}%-15s${NC} ${PURPLE}%-17s${NC} ${GREEN}%s${NC}\n" "$ip" "$mac" "$hostname"
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
# APPLY SPEED LIMIT (Suppressed errors)
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
        echo -e "${YELLOW}[*] Removing speed limit for $ip...${NC}"
        su -c "iptables -D FORWARD -s $ip -j DROP" &>/dev/null
        su -c "iptables -D FORWARD -d $ip -j DROP" &>/dev/null
        su -c "tc filter del dev $iface protocol ip parent 1:0 prio 1" &>/dev/null
        echo -e "${GREEN}[✓] Limit removed${NC}"
    else
        echo -e "${YELLOW}[*] Applying ${limit_kb} KB/s limit to $ip...${NC}"
        
        local limit_kbit=$((limit_kb * 8))
        
        su -c "tc qdisc show dev $iface | grep -q htb" &>/dev/null
        if [ $? -ne 0 ]; then
            su -c "tc qdisc add dev $iface root handle 1: htb default 30" &>/dev/null
            su -c "tc class add dev $iface parent 1: classid 1:1 htb rate 100mbit" &>/dev/null
        fi
        
        local class_id="1:$(echo $ip | cut -d. -f4)"
        
        su -c "tc class del dev $iface classid $class_id" &>/dev/null
        su -c "tc filter del dev $iface parent 1: protocol ip prio 1 u32 match ip dst $ip" &>/dev/null
        
        su -c "tc class add dev $iface parent 1:1 classid $class_id htb rate ${limit_kbit}kbit ceil ${limit_kbit}kbit" &>/dev/null
        su -c "tc filter add dev $iface parent 1: protocol ip prio 1 u32 match ip dst $ip flowid $class_id" &>/dev/null
        su -c "tc filter add dev $iface parent 1: protocol ip prio 1 u32 match ip src $ip flowid $class_id" &>/dev/null
        
        echo -e "${GREEN}[✓] Speed limit applied${NC}"
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
    
    echo -e "${YELLOW}Connected Clients (IPv4):${NC}\n"
    
    local -a client_list
    local count=1
    
    while IFS= read -r line; do
        client_list[$count]="$line"
        local ip=$(echo "$line" | awk '{print $1}')
        local mac=$(echo "$line" | awk '{print $2}')
        local hostname=$(get_client_hostname "$ip")
        local current_limit=$(grep "^$ip " "$CLIENTS_FILE" 2>/dev/null | awk '{print $2}')
        [ -z "$current_limit" ] && current_limit="∞"
        
        printf "${CYAN}%2d.${NC} ${WHITE}%-15s${NC} ${PURPLE}%-17s${NC} ${GREEN}%-20s${NC} ${YELLOW}%s KB/s${NC}\n" \
            "$count" "$ip" "$mac" "$hostname" "$current_limit"
        
        count=$((count + 1))
    done <<< "$clients"
    
    echo -e "\n${CYAN}0.${NC} All Clients"
    echo ""
    
    read -p "$(echo -e ${GREEN}Select client [0-$((count-1))]: ${NC})" selection
    read -p "$(echo -e ${GREEN}Speed limit in KB/s [0=unlimited]: ${NC})" speed_limit
    
    if ! [[ "$speed_limit" =~ ^[0-9]+$ ]]; then
        echo -e "${RED}[✗] Invalid speed value${NC}"
        sleep 1
        return
    fi
    
    if [ "$selection" == "0" ]; then
        echo -e "\n${YELLOW}[*] Applying to all clients...${NC}\n"
        for i in "${!client_list[@]}"; do
            local ip=$(echo "${client_list[$i]}" | awk '{print $1}')
            apply_speed_limit "$ip" "$speed_limit"
            sed -i "/^$ip /d" "$CLIENTS_FILE" 2>/dev/null
            echo "$ip $speed_limit" >> "$CLIENTS_FILE"
        done
        DEFAULT_SPEED_LIMIT=$speed_limit
        save_config
    elif [ "$selection" -ge 1 ] && [ "$selection" -lt "$count" ]; then
        local selected_client="${client_list[$selection]}"
        local ip=$(echo "$selected_client" | awk '{print $1}')
        echo ""
        apply_speed_limit "$ip" "$speed_limit"
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
        local hostname=$(get_client_hostname "$ip")
        printf "${CYAN}%2d.${NC} ${WHITE}%-15s${NC} ${PURPLE}%-17s${NC} ${GREEN}%s${NC}\n" "$count" "$ip" "$mac" "$hostname"
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
        printf "${CYAN}%2d.${NC} ${WHITE}%-15s${NC} ${PURPLE}%s${NC}\n" "$count" "$ip" "$mac"
        count=$((count + 1))
    done < "$BLOCKED_FILE"
    
    echo ""
    read -p "$(echo -e ${GREEN}Select client to unblock [1-$((count-1))]: ${NC})" selection
    
    if [ "$selection" -ge 1 ] && [ "$selection" -lt "$count" ]; then
        local selected_client="${blocked_list[$selection]}"
        local ip=$(echo "$selected_client" | awk '{print $1}')
        
        echo -e "\n${YELLOW}[*] Unblocking $ip...${NC}"
        
        su -c "iptables -D FORWARD -s $ip -j DROP" &>/dev/null
        su -c "iptables -D FORWARD -d $ip -j DROP" &>/dev/null
        
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
        local hostname=$(get_client_hostname "$ip")
        printf "${CYAN}%2d.${NC} ${WHITE}%-15s${NC} ${PURPLE}%-17s${NC} ${GREEN}%s${NC}\n" "$count" "$ip" "$mac" "$hostname"
        count=$((count + 1))
    done <<< "$clients"
    
    echo ""
    read -p "$(echo -e ${GREEN}Select client to kick [1-$((count-1))]: ${NC})" selection
    
    if [ "$selection" -ge 1 ] && [ "$selection" -lt "$count" ]; then
        local selected_client="${client_list[$selection]}"
        local ip=$(echo "$selected_client" | awk '{print $1}')
        
        echo -e "\n${YELLOW}[*] Kicking $ip...${NC}"
        
        detect_hotspot_interface
        su -c "ip neigh del $ip dev $HOTSPOT_INTERFACE" &>/dev/null
        su -c "arp -d $ip" &>/dev/null
        
        echo -e "${GREEN}[✓] Client kicked (may reconnect)${NC}"
    else
        echo -e "${RED}[✗] Invalid selection${NC}"
    fi
    
    echo ""
    read -p "Press Enter..."
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
                echo -e "${YELLOW}Connected Clients (IPv4):${NC}\n"
                while IFS= read -r line; do
                    local ip=$(echo "$line" | awk '{print $1}')
                    local mac=$(echo "$line" | awk '{print $2}')
                    local hostname=$(get_client_hostname "$ip")
                    local limit=$(grep "^$ip " "$CLIENTS_FILE" 2>/dev/null | awk '{print $2}')
                    [ -z "$limit" ] && limit="∞"
                    printf "${CYAN}•${NC} ${WHITE}%-15s${NC} ${PURPLE}%-17s${NC} ${GREEN}%-20s${NC} ${YELLOW}%s KB/s${NC}\n" "$ip" "$mac" "$hostname" "$limit"
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
        
        echo -e "${CYAN}1.${NC} Client Management"
        echo -e "${CYAN}2.${NC} Real-time Statistics"
        echo -e "${CYAN}3.${NC} About"
        echo -e "${CYAN}0.${NC} Exit"
        echo ""
        echo -e "${YELLOW}[!] Enable/Disable hotspot from Android Settings${NC}"
        echo -e "${CYAN}════════════════════════════════════════════════${NC}"
        
        read -p "$(echo -e ${GREEN}Choose: ${NC})" choice
        
        case $choice in
            1) client_management ;;
            2) realtime_stats ;;
            3) show_about ;;
            0)
                echo -e "\n${CYAN}Terima kasih!${NC}"
                echo -e "${PURPLE}Dibuat oleh Senzore, Alias Adam Sanjaya <3${NC}\n"
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
    
    echo -e "${WHITE}${BOLD}Hotspot Manager v2.1${NC}"
    echo -e "${YELLOW}Advanced Tethering Management for Android${NC}\n"
    
    echo -e "${CYAN}Features:${NC}"
    echo -e "${GREEN}✓${NC} Passive hotspot detection (Realme C15)"
    echo -e "${GREEN}✓${NC} IPv4 client detection with hostnames"
    echo -e "${GREEN}✓${NC} Real-time statistics"
    echo -e "${GREEN}✓${NC} Per-client speed limiting"
    echo -e "${GREEN}✓${NC} Client blocking/kicking"
    echo -e "${GREEN}✓${NC} Root & Magisk support"
    
    echo ""
    echo -e "${PURPLE}════════════════════════════════════════════════${NC}"
    echo -e "${PURPLE}${BOLD}      Dibuat oleh Senzore, Alias Adam Sanjaya <3${NC}"
    echo -e "${PURPLE}════════════════════════════════════════════════${NC}\n"
    
    echo -e "${YELLOW}Note: Root access required for full features${NC}"
    echo -e "${YELLOW}      Enable hotspot manually from Settings${NC}\n"
    
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
