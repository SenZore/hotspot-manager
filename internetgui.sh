#!/data/data/com.termux/files/usr/bin/bash

# ═══════════════════════════════════════════════════
# TERMUX HOTSPOT MANAGER v3.0 - OPTIMIZED
# By: senzore ganteng
# ═══════════════════════════════════════════════════

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m'
BOLD='\033[1m'

# Config
CONFIG_DIR="$HOME/.hotspot_manager"
CONFIG_FILE="$CONFIG_DIR/config.conf"
CLIENTS_DB="$CONFIG_DIR/clients.db"
BLOCKED_DB="$CONFIG_DIR/blocked.db"

# Global vars
ROOT=0
INTERFACE="wlan0"
ACTIVE=0

# ═══════════════════════════════════════════════════
# FAST BANNER
# ═══════════════════════════════════════════════════
banner() {
    clear
    echo -e "${CYAN}═══════════════════════════════════════════════════${NC}"
    echo -e "${WHITE}${BOLD}         HOTSPOT MANAGER v3.0${NC}"
    echo -e "${PURPLE}           By: senzore ganteng${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════${NC}\n"
}

# ═══════════════════════════════════════════════════
# QUICK ROOT CHECK
# ═══════════════════════════════════════════════════
check_root() {
    if su -c "id" 2>/dev/null | grep -q "uid=0"; then
        ROOT=1
        echo -e "${GREEN}[✓] Root: OK${NC}"
    else
        echo -e "${RED}[✗] Root: NO${NC}"
    fi
}

# ═══════════════════════════════════════════════════
# FAST DEPENDENCY INSTALL
# ═══════════════════════════════════════════════════
install_deps() {
    echo -e "${YELLOW}[*] Checking packages...${NC}"
    
    for pkg in iproute2 net-tools bc iptables ncurses-utils; do
        if ! dpkg -s "$pkg" &>/dev/null; then
            echo -e "${YELLOW}Installing $pkg...${NC}"
            pkg install -y "$pkg" &>/dev/null
        fi
    done
    
    echo -e "${GREEN}[✓] Dependencies ready${NC}"
}

# ═══════════════════════════════════════════════════
# QUICK INTERFACE DETECTION
# ═══════════════════════════════════════════════════
detect_interface() {
    [ $ROOT -eq 0 ] && return
    
    # Quick check for active interfaces
    for iface in ap0 swlan0 wlan0 rndis0; do
        if su -c "ip addr show $iface 2>/dev/null | grep -q 'inet '" 2>/dev/null; then
            INTERFACE="$iface"
            ACTIVE=1
            return
        fi
    done
}

# ═══════════════════════════════════════════════════
# DEVICE NAME BY MAC PREFIX
# ═══════════════════════════════════════════════════
device_name() {
    local mac="${1:-00:00:00}"
    local prefix="${mac:0:8}"
    
    case "${prefix^^}" in
        "00:0C:29"|"00:50:56") echo "VMware" ;;
        "2C:4D:54") echo "ASUS" ;;
        "38:D5:47"|"40:B0:76") echo "Samsung" ;;
        "3C:06:30"|"50:8F:4C") echo "Xiaomi/Redmi" ;;
        "44:01:BB"|"E4:C2:39") echo "OPPO/Realme" ;;
        "50:C7:BF") echo "TP-Link" ;;
        "74:60:FA"|"DC:72:23") echo "OnePlus" ;;
        "8C:79:67"|"48:01:C5") echo "Huawei" ;;
        "A4:C6:4F"|"10:5A:17") echo "Vivo" ;;
        "DC:72:9B"|"84:F0:29") echo "Infinix" ;;
        "F8:E9:4E"|"AC:EE:9E") echo "Apple" ;;
        *) echo "Device" ;;
    esac
}

# ═══════════════════════════════════════════════════
# INIT CONFIG
# ═══════════════════════════════════════════════════
init_config() {
    mkdir -p "$CONFIG_DIR"
    touch "$CLIENTS_DB" "$BLOCKED_DB"
    [ ! -f "$CONFIG_FILE" ] && echo "SPEED_LIMIT=0" > "$CONFIG_FILE"
}

# ═══════════════════════════════════════════════════
# GET CLIENTS - FAST VERSION
# ═══════════════════════════════════════════════════
get_clients() {
    [ $ROOT -eq 0 ] && return
    
    detect_interface
    
    # Direct ARP check - faster
    su -c "cat /proc/net/arp 2>/dev/null" | grep "$INTERFACE" | grep -v "00:00:00:00:00:00" | awk '{print $1" "$4}'
}

# ═══════════════════════════════════════════════════
# NETWORK STATS - SIMPLIFIED
# ═══════════════════════════════════════════════════
network_stats() {
    detect_interface
    local rx=$(cat /sys/class/net/$INTERFACE/statistics/rx_bytes 2>/dev/null || echo 0)
    local tx=$(cat /sys/class/net/$INTERFACE/statistics/tx_bytes 2>/dev/null || echo 0)
    
    echo "RX: $((rx/1048576)) MB | TX: $((tx/1048576)) MB"
}

# ═══════════════════════════════════════════════════
# REALTIME MONITOR - OPTIMIZED
# ═══════════════════════════════════════════════════
monitor_stats() {
    banner
    echo -e "${CYAN}═══════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}${BOLD}           REAL-TIME MONITOR${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════${NC}\n"
    
    detect_interface
    echo -e "${YELLOW}Interface: $INTERFACE${NC}"
    echo -e "${YELLOW}Press Ctrl+C to exit${NC}\n"
    
    local stats="/sys/class/net/$INTERFACE/statistics"
    
    if [ ! -f "$stats/rx_bytes" ]; then
        echo -e "${RED}[✗] Interface not active${NC}"
        read -p "Press Enter..."
        return
    fi
    
    # Hide cursor
    tput civis 2>/dev/null
    trap 'tput cnorm 2>/dev/null; echo' EXIT INT
    
    local prev_rx=$(cat $stats/rx_bytes)
    local prev_tx=$(cat $stats/tx_bytes)
    
    while true; do
        sleep 1
        
        local rx=$(cat $stats/rx_bytes)
        local tx=$(cat $stats/tx_bytes)
        
        local rx_rate=$(( (rx - prev_rx) / 1024 ))
        local tx_rate=$(( (tx - prev_tx) / 1024 ))
        
        [ $rx_rate -lt 0 ] && rx_rate=0
        [ $tx_rate -lt 0 ] && tx_rate=0
        
        # Clear and update
        tput cup 7 0
        tput ed
        
        echo -e "${GREEN}╔════════════════════════════════════════════════╗${NC}"
        echo -e "${GREEN}║${NC} Download: ${CYAN}$rx_rate KB/s${NC}"
        echo -e "${GREEN}║${NC} Upload:   ${CYAN}$tx_rate KB/s${NC}"
        echo -e "${GREEN}╠════════════════════════════════════════════════╣${NC}"
        echo -e "${GREEN}║${NC} Total RX: ${PURPLE}$((rx/1048576)) MB${NC}"
        echo -e "${GREEN}║${NC} Total TX: ${PURPLE}$((tx/1048576)) MB${NC}"
        echo -e "${GREEN}╚════════════════════════════════════════════════╝${NC}"
        
        if [ $ROOT -eq 1 ]; then
            echo -e "\n${YELLOW}Connected Devices:${NC}"
            
            local clients=$(get_clients)
            if [ -n "$clients" ]; then
                while read ip mac; do
                    [ -z "$ip" ] && continue
                    local name=$(device_name "$mac")
                    local limit=$(grep "^$ip " "$CLIENTS_DB" 2>/dev/null | cut -d' ' -f2)
                    [ -z "$limit" ] || [ "$limit" = "0" ] && limit="∞" || limit="${limit}KB/s"
                    
                    echo -e "  ${CYAN}•${NC} $ip │ ${WHITE}$name${NC} │ ${YELLOW}$limit${NC}"
                done <<< "$clients"
            else
                echo -e "  ${RED}No devices${NC}"
            fi
        fi
        
        prev_rx=$rx
        prev_tx=$tx
    done
}

# ═══════════════════════════════════════════════════
# SPEED LIMIT - SIMPLIFIED
# ═══════════════════════════════════════════════════
set_speed() {
    [ $ROOT -eq 0 ] && echo -e "${RED}Root required${NC}" && return
    
    banner
    echo -e "${CYAN}═══════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}${BOLD}          SPEED CONTROL${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════${NC}\n"
    
    local clients=$(get_clients)
    [ -z "$clients" ] && echo -e "${RED}No clients${NC}" && read -p "Press Enter..." && return
    
    echo -e "${YELLOW}Connected Devices:${NC}\n"
    
    local -a list
    local i=1
    
    while read ip mac; do
        [ -z "$ip" ] && continue
        list[$i]="$ip $mac"
        local name=$(device_name "$mac")
        local limit=$(grep "^$ip " "$CLIENTS_DB" 2>/dev/null | cut -d' ' -f2)
        [ -z "$limit" ] || [ "$limit" = "0" ] && limit="unlimited" || limit="${limit}KB/s"
        
        printf "${CYAN}%2d.${NC} %-15s │ ${WHITE}%-12s${NC} │ ${YELLOW}%s${NC}\n" $i "$ip" "$name" "$limit"
        ((i++))
    done <<< "$clients"
    
    echo -e "\n${CYAN}0.${NC} All devices"
    
    read -p $'\n'"Select [0-$((i-1))]: " sel
    read -p "Speed limit (KB/s, 0=unlimited): " speed
    
    [[ ! "$speed" =~ ^[0-9]+$ ]] && echo -e "${RED}Invalid${NC}" && return
    
    detect_interface
    
    apply_limit() {
        local ip=$1
        echo -e "${YELLOW}Setting $ip to ${speed}KB/s...${NC}"
        
        if [ "$speed" = "0" ]; then
            su -c "tc filter del dev $INTERFACE protocol ip parent 1:0 prio 1 2>/dev/null"
            sed -i "/^$ip /d" "$CLIENTS_DB" 2>/dev/null
        else
            # Setup tc if needed
            su -c "tc qdisc show dev $INTERFACE | grep -q htb" || \
                su -c "tc qdisc add dev $INTERFACE root handle 1: htb default 30 && \
                       tc class add dev $INTERFACE parent 1: classid 1:1 htb rate 100mbit"
            
            local kbit=$((speed * 8))
            local cid="1:$(echo $ip | cut -d. -f4)"
            
            su -c "tc class replace dev $INTERFACE parent 1:1 classid $cid htb rate ${kbit}kbit"
            su -c "tc filter add dev $INTERFACE parent 1: protocol ip prio 1 u32 match ip dst $ip flowid $cid"
            
            sed -i "/^$ip /d" "$CLIENTS_DB" 2>/dev/null
            echo "$ip $speed" >> "$CLIENTS_DB"
        fi
        echo -e "${GREEN}[✓] Done${NC}"
    }
    
    if [ "$sel" = "0" ]; then
        for j in "${!list[@]}"; do
            [ -z "${list[$j]}" ] && continue
            apply_limit $(echo ${list[$j]} | cut -d' ' -f1)
        done
    elif [ "$sel" -ge 1 ] && [ "$sel" -lt "$i" ]; then
        apply_limit $(echo ${list[$sel]} | cut -d' ' -f1)
    fi
    
    read -p "Press Enter..."
}

# ═══════════════════════════════════════════════════
# BLOCK CLIENT - FAST
# ═══════════════════════════════════════════════════
block_client() {
    [ $ROOT -eq 0 ] && echo -e "${RED}Root required${NC}" && return
    
    banner
    echo -e "${CYAN}═══════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}${BOLD}          BLOCK DEVICE${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════${NC}\n"
    
    local clients=$(get_clients)
    [ -z "$clients" ] && echo -e "${RED}No clients${NC}" && read -p "Press Enter..." && return
    
    echo -e "${YELLOW}Select device to block:${NC}\n"
    
    local i=1
    local -a list
    
    while read ip mac; do
        [ -z "$ip" ] && continue
        list[$i]="$ip $mac"
        printf "${CYAN}%2d.${NC} %-15s │ ${WHITE}%s${NC}\n" $i "$ip" "$(device_name "$mac")"
        ((i++))
    done <<< "$clients"
    
    read -p $'\n'"Select [1-$((i-1))]: " sel
    
    if [ "$sel" -ge 1 ] && [ "$sel" -lt "$i" ]; then
        local ip=$(echo ${list[$sel]} | cut -d' ' -f1)
        local mac=$(echo ${list[$sel]} | cut -d' ' -f2)
        
        echo -e "\n${YELLOW}Blocking $ip...${NC}"
        su -c "iptables -I FORWARD -s $ip -j DROP"
        echo "$ip $mac" >> "$BLOCKED_DB"
        echo -e "${GREEN}[✓] Blocked${NC}"
    fi
    
    read -p "Press Enter..."
}

# ═══════════════════════════════════════════════════
# UNBLOCK CLIENT
# ═══════════════════════════════════════════════════
unblock_client() {
    [ $ROOT -eq 0 ] && echo -e "${RED}Root required${NC}" && return
    
    banner
    echo -e "${CYAN}═══════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}${BOLD}         UNBLOCK DEVICE${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════${NC}\n"
    
    [ ! -s "$BLOCKED_DB" ] && echo -e "${RED}No blocked devices${NC}" && read -p "Press Enter..." && return
    
    echo -e "${YELLOW}Blocked devices:${NC}\n"
    
    local i=1
    local -a list
    
    while read line; do
        [ -z "$line" ] && continue
        list[$i]="$line"
        local ip=$(echo $line | cut -d' ' -f1)
        local mac=$(echo $line | cut -d' ' -f2)
        printf "${CYAN}%2d.${NC} %-15s │ ${WHITE}%s${NC}\n" $i "$ip" "$(device_name "$mac")"
        ((i++))
    done < "$BLOCKED_DB"
    
    read -p $'\n'"Select [1-$((i-1))]: " sel
    
    if [ "$sel" -ge 1 ] && [ "$sel" -lt "$i" ]; then
        local ip=$(echo ${list[$sel]} | cut -d' ' -f1)
        
        echo -e "\n${YELLOW}Unblocking $ip...${NC}"
        su -c "iptables -D FORWARD -s $ip -j DROP 2>/dev/null"
        sed -i "/^$ip /d" "$BLOCKED_DB"
        echo -e "${GREEN}[✓] Unblocked${NC}"
    fi
    
    read -p "Press Enter..."
}

# ═══════════════════════════════════════════════════
# KICK CLIENT
# ═══════════════════════════════════════════════════
kick_client() {
    [ $ROOT -eq 0 ] && echo -e "${RED}Root required${NC}" && return
    
    banner
    echo -e "${CYAN}═══════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}${BOLD}          KICK DEVICE${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════${NC}\n"
    
    local clients=$(get_clients)
    [ -z "$clients" ] && echo -e "${RED}No clients${NC}" && read -p "Press Enter..." && return
    
    echo -e "${YELLOW}Select device to kick:${NC}\n"
    
    local i=1
    local -a list
    
    while read ip mac; do
        [ -z "$ip" ] && continue
        list[$i]="$ip"
        printf "${CYAN}%2d.${NC} %-15s │ ${WHITE}%s${NC}\n" $i "$ip" "$(device_name "$mac")"
        ((i++))
    done <<< "$clients"
    
    read -p $'\n'"Select [1-$((i-1))]: " sel
    
    if [ "$sel" -ge 1 ] && [ "$sel" -lt "$i" ]; then
        detect_interface
        local ip="${list[$sel]}"
        
        echo -e "\n${YELLOW}Kicking $ip...${NC}"
        su -c "ip neigh del $ip dev $INTERFACE 2>/dev/null"
        su -c "arp -d $ip 2>/dev/null"
        echo -e "${GREEN}[✓] Kicked${NC}"
    fi
    
    read -p "Press Enter..."
}

# ═══════════════════════════════════════════════════
# CLIENT MENU
# ═══════════════════════════════════════════════════
client_menu() {
    while true; do
        banner
        echo -e "${CYAN}═══════════════════════════════════════════════════${NC}"
        echo -e "${CYAN}${BOLD}         DEVICE MANAGEMENT${NC}"
        echo -e "${CYAN}═══════════════════════════════════════════════════${NC}\n"
        
        if [ $ROOT -eq 1 ]; then
            local clients=$(get_clients)
            if [ -n "$clients" ]; then
                echo -e "${YELLOW}Connected:${NC}\n"
                while read ip mac; do
                    [ -z "$ip" ] && continue
                    local name=$(device_name "$mac")
                    local limit=$(grep "^$ip " "$CLIENTS_DB" 2>/dev/null | cut -d' ' -f2)
                    [ -z "$limit" ] || [ "$limit" = "0" ] && limit="∞" || limit="${limit}KB/s"
                    
                    printf "${CYAN}•${NC} %-15s │ ${WHITE}%-12s${NC} │ ${YELLOW}%s${NC}\n" "$ip" "$name" "$limit"
                done <<< "$clients"
            else
                echo -e "${RED}No devices connected${NC}"
            fi
        fi
        
        echo -e "\n${CYAN}═══════════════════════════════════════════════════${NC}"
        echo -e "${CYAN}1.${NC} Speed Control"
        echo -e "${CYAN}2.${NC} Block Device"
        echo -e "${CYAN}3.${NC} Unblock Device"
        echo -e "${CYAN}4.${NC} Kick Device"
        echo -e "${CYAN}0.${NC} Back"
        echo -e "${CYAN}═══════════════════════════════════════════════════${NC}"
        
        read -p $'\n'"Choose: " opt
        
        case $opt in
            1) set_speed ;;
            2) block_client ;;
            3) unblock_client ;;
            4) kick_client ;;
            0) break ;;
        esac
    done
}

# ═══════════════════════════════════════════════════
# ABOUT
# ═══════════════════════════════════════════════════
about() {
    banner
    echo -e "${CYAN}═══════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}${BOLD}                ABOUT${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════${NC}\n"
    
    echo -e "${WHITE}${BOLD}Hotspot Manager v3.0${NC}"
    echo -e "${YELLOW}Fast & Optimized Edition${NC}\n"
    
    echo -e "${CYAN}Features:${NC}"
    echo -e "${GREEN}✓${NC} Instant device detection"
    echo -e "${GREEN}✓${NC} Speed control per device"
    echo -e "${GREEN}✓${NC} Block/Kick management"
    echo -e "${GREEN}✓${NC} Real-time monitoring"
    echo -e "${GREEN}✓${NC} Vendor identification"
    
    echo -e "\n${PURPLE}═══════════════════════════════════════════════════${NC}"
    echo -e "${PURPLE}${BOLD}         By: senzore ganteng${NC}"
    echo -e "${PURPLE}═══════════════════════════════════════════════════${NC}\n"
    
    read -p "Press Enter..."
}

# ═══════════════════════════════════════════════════
# MAIN MENU
# ═══════════════════════════════════════════════════
main_menu() {
    while true; do
        banner
        detect_interface
        
        echo -e "${CYAN}═══════════════════════════════════════════════════${NC}"
        echo -e "${CYAN}${BOLD}             STATUS${NC}"
        echo -e "${CYAN}═══════════════════════════════════════════════════${NC}\n"
        
        echo -e "${YELLOW}Root:${NC}      $([ $ROOT -eq 1 ] && echo -e "${GREEN}YES${NC}" || echo -e "${RED}NO${NC}")"
        echo -e "${YELLOW}Interface:${NC} ${GREEN}$INTERFACE${NC}"
        echo -e "${YELLOW}Network:${NC}   $(network_stats)"
        
        echo -e "\n${CYAN}═══════════════════════════════════════════════════${NC}"
        echo -e "${CYAN}${BOLD}             MENU${NC}"
        echo -e "${CYAN}═══════════════════════════════════════════════════${NC}\n"
        
        echo -e "${CYAN}1.${NC} Device Management"
        echo -e "${CYAN}2.${NC} Real-time Monitor"
        echo -e "${CYAN}3.${NC} About"
        echo -e "${CYAN}0.${NC} Exit"
        
        echo -e "\n${CYAN}═══════════════════════════════════════════════════${NC}"
        
        read -p $'\n'"Choose: " opt
        
        case $opt in
            1) client_menu ;;
            2) monitor_stats ;;
            3) about ;;
            0) echo -e "\n${PURPLE}By: senzore ganteng${NC}\n"; exit ;;
        esac
    done
}

# ═══════════════════════════════════════════════════
# MAIN
# ═══════════════════════════════════════════════════
main() {
    # Clean install
    [ "$1" = "--clean" ] || [ "$1" = "-c" ] && rm -rf "$CONFIG_DIR"
    
    banner
    echo -e "${CYAN}Starting...${NC}\n"
    
    check_root
    install_deps
    init_config
    
    echo -e "${GREEN}[✓] Ready${NC}\n"
    read -p "Press Enter to continue..."
    
    main_menu
}

# RUN
main "$@"
