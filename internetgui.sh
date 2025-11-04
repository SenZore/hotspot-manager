#!/data/data/com.termux/files/usr/bin/bash

# ═══════════════════════════════════════════════════
# TERMUX HOTSPOT MANAGER v2.3
# By: senzore ganteng
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
# CLEAN REINSTALL CHECK
# ═══════════════════════════════════════════════════
check_clean_install() {
    if [ "$1" == "--clean" ] || [ "$1" == "-c" ]; then
        echo -e "${YELLOW}[*] Performing clean reinstall...${NC}"
        rm -rf "$CONFIG_DIR" 2>/dev/null
        echo -e "${GREEN}[✓] Config cleared${NC}"
        sleep 1
    fi
}

# ═══════════════════════════════════════════════════
# SIMPLE BANNER
# ═══════════════════════════════════════════════════
show_banner() {
    clear
    echo -e "${CYAN}═══════════════════════════════════════════════════${NC}"
    echo -e "${WHITE}${BOLD}         HOTSPOT MANAGER v2.3${NC}"
    echo -e "${PURPLE}           By: senzore ganteng${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════${NC}\n"
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
    
    # Required packages (fixed list)
    PACKAGES=("termux-api" "iproute2" "net-tools" "procps" "grep" "sed" "bc" "iptables" "ncurses-utils")
    
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
# DETECT HOTSPOT/TETHERING INTERFACE (IMPROVED)
# ═══════════════════════════════════════════════════
detect_hotspot_interface() {
    if [ $ROOT_AVAILABLE -eq 0 ]; then
        HOTSPOT_INTERFACE="wlan0"
        return
    fi
    
    TETHERING_ACTIVE=0
    
    # Get all network interfaces
    local all_ifaces=$(su -c "ip link show 2>/dev/null | grep -E '^[0-9]+:' | awk -F': ' '{print \$2}'" | tr -d ' ')
    
    # Check for interfaces with typical hotspot IP ranges
    for iface in $all_ifaces; do
        # Skip loopback
        [ "$iface" == "lo" ] && continue
        
        # Check if interface has IP in hotspot range
        local has_hotspot_ip=$(su -c "ip addr show $iface 2>/dev/null | grep -E 'inet (192\.168\.|10\.|172\.)' | grep -v '127.0.0.1'" 2>/dev/null)
        
        if [ -n "$has_hotspot_ip" ]; then
            # Check if it's actually serving as gateway
            local ip=$(echo "$has_hotspot_ip" | awk '{print $2}' | cut -d/ -f1)
            if [[ "$ip" =~ \.1$ ]] || [[ "$ip" =~ \.254$ ]]; then
                HOTSPOT_INTERFACE="$iface"
                TETHERING_ACTIVE=1
                return
            fi
        fi
    done
    
    # Fallback: Check common interface names
    for iface in ap0 swlan0 softap0 wlan0 rndis0; do
        if echo "$all_ifaces" | grep -q "^$iface$"; then
            # Check if UP
            if su -c "ip link show $iface 2>/dev/null | grep -q 'state UP'" 2>/dev/null; then
                HOTSPOT_INTERFACE="$iface"
                TETHERING_ACTIVE=1
                return
            fi
        fi
    done
    
    # Default fallback
    HOTSPOT_INTERFACE="wlan0"
}

# ═══════════════════════════════════════════════════
# GET DEVICE NAME FROM MAC (SIMPLIFIED)
# ═══════════════════════════════════════════════════
get_device_name() {
    local mac=$1
    local device_name=""
    
    # Skip if no MAC
    [ -z "$mac" ] || [ "$mac" == "00:00:00:00:00:00" ] && echo "Unknown" && return
    
    # Get vendor from MAC prefix
    local vendor_prefix=$(echo "$mac" | cut -d: -f1-3 | tr '[:lower:]' '[:upper:]')
    
    case $vendor_prefix in
        "00:0C:29"|"00:50:56") device_name="VMware" ;;
        "00:1B:44"|"00:1C:14"|"00:E0:4C") device_name="Realtek" ;;
        "2C:4D:54") device_name="ASUS" ;;
        "38:D5:47"|"40:B0:76"|"84:11:9E") device_name="Samsung" ;;
        "3C:06:30"|"50:8F:4C"|"7C:1D:D9") device_name="Xiaomi" ;;
        "44:01:BB"|"E4:C2:39"|"AC:56:1C") device_name="OPPO/Realme" ;;
        "50:C7:BF") device_name="TP-Link" ;;
        "74:60:FA"|"DC:72:23") device_name="OPPO/OnePlus" ;;
        "8C:79:67"|"48:01:C5") device_name="Huawei" ;;
        "94:65:2D"|"C0:EE:FB") device_name="OnePlus" ;;
        "A4:C6:4F"|"10:5A:17") device_name="Vivo" ;;
        "DC:72:9B"|"84:F0:29") device_name="Infinix" ;;
        "F8:E9:4E"|"AC:EE:9E") device_name="Apple" ;;
        *) device_name="Device" ;;
    esac
    
    echo "$device_name"
}

# ═══════════════════════════════════════════════════
# INITIALIZE CONFIG
# ═══════════════════════════════════════════════════
init_config() {
    mkdir -p "$CONFIG_DIR"
    
    if [ ! -f "$CONFIG_FILE" ]; then
        cat > "$CONFIG_FILE" << EOF
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
    # Set default if not set
    DEFAULT_SPEED_LIMIT=${DEFAULT_SPEED_LIMIT:-0}
}

# ═══════════════════════════════════════════════════
# SAVE CONFIG
# ═══════════════════════════════════════════════════
save_config() {
    cat > "$CONFIG_FILE" << EOF
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
# GET CONNECTED CLIENTS (FIXED - like original)
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
# REALTIME STATS MONITOR (FIXED)
# ═══════════════════════════════════════════════════
realtime_stats() {
    show_banner
    echo -e "${CYAN}═══════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}${BOLD}           REAL-TIME STATISTICS${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════${NC}\n"
    
    # Force detection
    detect_hotspot_interface
    local interface=$HOTSPOT_INTERFACE
    
    echo -e "${YELLOW}Detecting active interface...${NC}"
    
    # Try to find active tethering interface more aggressively
    if [ $ROOT_AVAILABLE -eq 1 ]; then
        # List all interfaces with IPs
        echo -e "${CYAN}Checking interfaces...${NC}"
        
        # Find interface serving as gateway
        for test_iface in $(su -c "ip link show | grep -E '^[0-9]+:' | awk -F': ' '{print \$2}' | tr -d ' '" 2>/dev/null); do
            # Skip lo
            [ "$test_iface" == "lo" ] && continue
            
            # Check if has gateway IP
            local test_ip=$(su -c "ip addr show $test_iface 2>/dev/null | grep 'inet ' | grep -v '127.0.0.1' | awk '{print \$2}'" | cut -d/ -f1)
            
            if [ -n "$test_ip" ] && [[ "$test_ip" =~ (192\.168\.|10\.|172\.) ]]; then
                # Check if stats file exists
                if [ -f "/sys/class/net/$test_iface/statistics/rx_bytes" ] || su -c "[ -f /sys/class/net/$test_iface/statistics/rx_bytes ]" 2>/dev/null; then
                    interface="$test_iface"
                    echo -e "${GREEN}[✓] Found active interface: $interface ($test_ip)${NC}"
                    break
                fi
            fi
        done
    fi
    
    echo -e "${CYAN}Using Interface: $interface${NC}"
    echo -e "${YELLOW}Press Ctrl+C to exit${NC}\n"
    
    # Check access to stats
    local stats_readable=0
    if [ -f "/sys/class/net/$interface/statistics/rx_bytes" ]; then
        stats_readable=1
    elif [ $ROOT_AVAILABLE -eq 1 ] && su -c "[ -f /sys/class/net/$interface/statistics/rx_bytes ]" 2>/dev/null; then
        stats_readable=1
    fi
    
    if [ $stats_readable -eq 0 ]; then
        echo -e "${RED}[✗] Cannot read statistics for $interface${NC}"
        echo -e "${YELLOW}[!] Please make sure hotspot is active${NC}"
        read -p "Press Enter to continue..."
        return
    fi
    
    # Get initial values
    local prev_rx=0
    local prev_tx=0
    
    if [ $ROOT_AVAILABLE -eq 1 ]; then
        prev_rx=$(su -c "cat /sys/class/net/$interface/statistics/rx_bytes 2>/dev/null" || echo 0)
        prev_tx=$(su -c "cat /sys/class/net/$interface/statistics/tx_bytes 2>/dev/null" || echo 0)
    else
        prev_rx=$(cat /sys/class/net/$interface/statistics/rx_bytes 2>/dev/null || echo 0)
        prev_tx=$(cat /sys/class/net/$interface/statistics/tx_bytes 2>/dev/null || echo 0)
    fi
    
    # Ensure valid starting values
    prev_rx=${prev_rx:-0}
    prev_tx=${prev_tx:-0}
    
    # Hide cursor
    tput civis 2>/dev/null
    
    # Trap to restore cursor on exit
    trap 'tput cnorm 2>/dev/null' EXIT INT TERM
    
    while true; do
        sleep 1
        
        local curr_rx=0
        local curr_tx=0
        
        if [ $ROOT_AVAILABLE -eq 1 ]; then
            curr_rx=$(su -c "cat /sys/class/net/$interface/statistics/rx_bytes 2>/dev/null" || echo 0)
            curr_tx=$(su -c "cat /sys/class/net/$interface/statistics/tx_bytes 2>/dev/null" || echo 0)
        else
            curr_rx=$(cat /sys/class/net/$interface/statistics/rx_bytes 2>/dev/null || echo 0)
            curr_tx=$(cat /sys/class/net/$interface/statistics/tx_bytes 2>/dev/null || echo 0)
        fi
        
        # Ensure valid values
        curr_rx=${curr_rx:-0}
        curr_tx=${curr_tx:-0}
        
        local rx_rate=$((curr_rx - prev_rx))
        local tx_rate=$((curr_tx - prev_tx))
        
        # Prevent negative values
        [ $rx_rate -lt 0 ] && rx_rate=0
        [ $tx_rate -lt 0 ] && tx_rate=0
        
        local rx_kbs=$(echo "scale=2; $rx_rate / 1024" | bc 2>/dev/null || echo "0")
        local tx_kbs=$(echo "scale=2; $tx_rate / 1024" | bc 2>/dev/null || echo "0")
        
        local total_rx_mb=$(echo "scale=2; $curr_rx / 1048576" | bc 2>/dev/null || echo "0")
        local total_tx_mb=$(echo "scale=2; $curr_tx / 1048576" | bc 2>/dev/null || echo "0")
        
        # Move cursor and clear
        tput cup 10 0 2>/dev/null
        tput ed 2>/dev/null
        
        echo -e "${GREEN}╔════════════════════════════════════════════════╗${NC}"
        echo -e "${GREEN}║${NC} Download Speed:  ${CYAN}${rx_kbs} KB/s${NC}                  "
        echo -e "${GREEN}║${NC} Upload Speed:    ${CYAN}${tx_kbs} KB/s${NC}                  "
        echo -e "${GREEN}╠════════════════════════════════════════════════╣${NC}"
        echo -e "${GREEN}║${NC} Total Download:  ${PURPLE}${total_rx_mb} MB${NC}             "
        echo -e "${GREEN}║${NC} Total Upload:    ${PURPLE}${total_tx_mb} MB${NC}             "
        echo -e "${GREEN}╚════════════════════════════════════════════════╝${NC}"
        
        if [ $ROOT_AVAILABLE -eq 1 ]; then
            echo -e "\n${YELLOW}Connected Clients:${NC}"
            local clients=$(get_connected_clients)
            if [ -n "$clients" ]; then
                echo "$clients" | while read ip mac; do
                    [ -z "$ip" ] && continue
                    local device_name=$(get_device_name "$mac")
                    local limit=$(grep "^$ip " "$CLIENTS_FILE" 2>/dev/null | awk '{print $2}')
                    [ -z "$limit" ] || [ "$limit" == "0" ] && limit="∞" || limit="${limit} KB/s"
                    echo -e "  ${CYAN}•${NC} $ip - ${WHITE}$device_name${NC} (Speed: ${YELLOW}$limit${NC})"
                done
            else
                echo -e "  ${RED}No clients${NC}"
            fi
        fi
        
        prev_rx=$curr_rx
        prev_tx=$curr_tx
    done
    
    # Restore cursor
    tput cnorm 2>/dev/null
}

# ═══════════════════════════════════════════════════
# APPLY SPEED LIMIT
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
    echo -e "${CYAN}═══════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}${BOLD}         SET CLIENT SPEED LIMIT${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════${NC}\n"
    
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
        local device_name=$(get_device_name "$mac")
        local current_limit=$(grep "^$ip " "$CLIENTS_FILE" 2>/dev/null | awk '{print $2}')
        [ -z "$current_limit" ] || [ "$current_limit" == "0" ] && current_limit="unlimited" || current_limit="${current_limit} KB/s"
        
        printf "${CYAN}%2d.${NC} IP: ${WHITE}%-15s${NC} ${PURPLE}%-17s${NC} ${GREEN}%-12s${NC} Limit: ${YELLOW}%s${NC}\n" \
            "$count" "$ip" "$mac" "$device_name" "$current_limit"
        
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
    echo -e "${CYAN}═══════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}${BOLD}              BLOCK CLIENT${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════${NC}\n"
    
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
        local device_name=$(get_device_name "$mac")
        printf "${CYAN}%2d.${NC} IP: ${WHITE}%-15s${NC} ${PURPLE}%-17s${NC} ${GREEN}%s${NC}\n" "$count" "$ip" "$mac" "$device_name"
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
    echo -e "${CYAN}═══════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}${BOLD}            UNBLOCK CLIENT${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════${NC}\n"
    
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
        local device_name=$(get_device_name "$mac")
        printf "${CYAN}%2d.${NC} IP: ${WHITE}%-15s${NC} ${PURPLE}%-17s${NC} ${GREEN}%s${NC}\n" "$count" "$ip" "$mac" "$device_name"
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
    echo -e "${CYAN}═══════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}${BOLD}              KICK CLIENT${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════${NC}\n"
    
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
        local device_name=$(get_device_name "$mac")
        printf "${CYAN}%2d.${NC} IP: ${WHITE}%-15s${NC} ${PURPLE}%-17s${NC} ${GREEN}%s${NC}\n" "$count" "$ip" "$mac" "$device_name"
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
# CLIENT MANAGEMENT MENU
# ═══════════════════════════════════════════════════
client_management() {
    while true; do
        show_banner
        echo -e "${CYAN}═══════════════════════════════════════════════════${NC}"
        echo -e "${CYAN}${BOLD}           CLIENT MANAGEMENT${NC}"
        echo -e "${CYAN}═══════════════════════════════════════════════════${NC}\n"
        
        if [ $ROOT_AVAILABLE -eq 1 ]; then
            local clients=$(get_connected_clients)
            if [ -n "$clients" ]; then
                echo -e "${YELLOW}Connected Clients:${NC}\n"
                while IFS= read -r line; do
                    local ip=$(echo "$line" | awk '{print $1}')
                    local mac=$(echo "$line" | awk '{print $2}')
                    local device_name=$(get_device_name "$mac")
                    local limit=$(grep "^$ip " "$CLIENTS_FILE" 2>/dev/null | awk '{print $2}')
                    [ -z "$limit" ] || [ "$limit" == "0" ] && limit="∞" || limit="${limit} KB/s"
                    printf "${CYAN}•${NC} ${WHITE}%-15s${NC} ${PURPLE}%-17s${NC} ${GREEN}%-12s${NC} ${YELLOW}%s${NC}\n" "$ip" "$mac" "$device_name" "$limit"
                done <<< "$clients"
            else
                echo -e "${RED}No clients connected${NC}"
            fi
        else
            echo -e "${RED}Root required${NC}"
        fi
        
        echo ""
        echo -e "${CYAN}═══════════════════════════════════════════════════${NC}"
        echo -e "${CYAN}1.${NC} Set Speed Limit"
        echo -e "${CYAN}2.${NC} Block Client"
        echo -e "${CYAN}3.${NC} Unblock Client"
        echo -e "${CYAN}4.${NC} Kick Client"
        echo -e "${CYAN}0.${NC} Back"
        echo -e "${CYAN}═══════════════════════════════════════════════════${NC}"
        
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
        
        echo -e "${CYAN}═══════════════════════════════════════════════════${NC}"
        echo -e "${CYAN}${BOLD}              SYSTEM STATUS${NC}"
        echo -e "${CYAN}═══════════════════════════════════════════════════${NC}\n"
        
        echo -e "${YELLOW}Root:${NC}     $([ $ROOT_AVAILABLE -eq 1 ] && echo -e ${GREEN}Available || echo -e ${RED}No)${NC}"
        echo -e "${YELLOW}Magisk:${NC}   $([ $MAGISK_AVAILABLE -eq 1 ] && echo -e ${GREEN}Detected || echo -e ${RED}No)${NC}"
        echo -e "${YELLOW}Hotspot:${NC}  $(get_hotspot_status)"
        echo -e "${YELLOW}Network:${NC}  $(get_network_stats)"
        
        echo ""
        echo -e "${CYAN}═══════════════════════════════════════════════════${NC}"
        echo -e "${CYAN}${BOLD}               MAIN MENU${NC}"
        echo -e "${CYAN}═══════════════════════════════════════════════════${NC}\n"
        
        echo -e "${CYAN}1.${NC} Client Management"
        echo -e "${CYAN}2.${NC} Real-time Statistics"
        echo -e "${CYAN}3.${NC} About"
        echo -e "${CYAN}0.${NC} Exit"
        echo ""
        echo -e "${CYAN}═══════════════════════════════════════════════════${NC}"
        
        read -p "$(echo -e ${GREEN}Choose: ${NC})" choice
        
        case $choice in
            1) client_management ;;
            2) realtime_stats ;;
            3) show_about ;;
            0)
                echo -e "\n${CYAN}Thank you!${NC}"
                echo -e "${PURPLE}By: senzore ganteng${NC}\n"
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
    echo -e "${CYAN}═══════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}${BOLD}                 ABOUT${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════${NC}\n"
    
    echo -e "${WHITE}${BOLD}Hotspot Manager v2.3${NC}"
    echo -e "${YELLOW}Advanced Tethering Management for Android${NC}\n"
    
    echo -e "${CYAN}Features:${NC}"
    echo -e "${GREEN}✓${NC} Root & Magisk detection"
    echo -e "${GREEN}✓${NC} Real-time statistics"
    echo -e "${GREEN}✓${NC} Per-client speed limiting"
    echo -e "${GREEN}✓${NC} Client blocking/kicking"
    echo -e "${GREEN}✓${NC} Device identification"
    echo -e "${GREEN}✓${NC} Realme/ColorOS optimized"
    
    echo ""
    echo -e "${PURPLE}═══════════════════════════════════════════════════${NC}"
    echo -e "${PURPLE}${BOLD}            By: senzore ganteng${NC}"
    echo -e "${PURPLE}═══════════════════════════════════════════════════${NC}\n"
    
    echo -e "${YELLOW}Note: Root access required for most features${NC}"
    echo -e "${YELLOW}Usage: $0 [--clean|-c] for clean reinstall${NC}\n"
    
    read -p "Press Enter..."
}

# ═══════════════════════════════════════════════════
# MAIN EXECUTION
# ═══════════════════════════════════════════════════
main() {
    # Check for clean install
    check_clean_install "$1"
    
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
main "$@"
