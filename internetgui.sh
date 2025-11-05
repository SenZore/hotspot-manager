#!/data/data/com.termux/files/usr/bin/bash

# ═══════════════════════════════════════════════════
# HOTSPOT MANAGER v12.0 - SIMPLE & WORKING
# By: senzore ganteng
# ═══════════════════════════════════════════════════

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# Config
CONFIG_DIR="$HOME/.hotspot_manager"
SPEED_DB="$CONFIG_DIR/speed.db"
BLOCK_DB="$CONFIG_DIR/block.db"

# Variables
ROOT=0
INTERFACE="wlan0"

# ═══════════════════════════════════════════════════
# BANNER
# ═══════════════════════════════════════════════════
banner() {
    clear
    echo -e "${CYAN}═══════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}        HOTSPOT MANAGER v12.0${NC}"
    echo -e "${CYAN}         By: senzore ganteng${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════${NC}\n"
}

# ═══════════════════════════════════════════════════
# CHECK ROOT
# ═══════════════════════════════════════════════════
check_root() {
    if su -c "id" 2>/dev/null | grep -q "uid=0"; then
        ROOT=1
        echo -e "${GREEN}[✓] Root Access OK${NC}"
        
        # Set TTL to 65
        su -c "iptables -t mangle -A POSTROUTING -j TTL --ttl-set 65" 2>/dev/null
        su -c "echo 65 > /proc/sys/net/ipv4/ip_default_ttl" 2>/dev/null
        
        # Enable forwarding
        su -c "echo 1 > /proc/sys/net/ipv4/ip_forward" 2>/dev/null
    else
        echo -e "${RED}[✗] No Root Access${NC}"
        echo -e "${YELLOW}This app needs root!${NC}"
        sleep 2
        exit 1
    fi
}

# ═══════════════════════════════════════════════════
# FIND INTERFACE
# ═══════════════════════════════════════════════════
find_interface() {
    # Try to find active hotspot interface
    for iface in ap0 swlan0 wlan0; do
        if su -c "ip link show $iface" 2>/dev/null | grep -q "state UP"; then
            INTERFACE="$iface"
            return
        fi
    done
}

# ═══════════════════════════════════════════════════
# GET CONNECTED CLIENTS
# ═══════════════════════════════════════════════════
get_clients() {
    find_interface
    su -c "arp -n 2>/dev/null | grep -v incomplete | grep $INTERFACE | awk '{print \$1}' | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$'"
}

# ═══════════════════════════════════════════════════
# LIST CLIENTS
# ═══════════════════════════════════════════════════
list_clients() {
    echo -e "${YELLOW}Connected Devices:${NC}\n"
    
    local clients=$(get_clients)
    if [ -z "$clients" ]; then
        echo -e "${RED}No devices connected${NC}"
        return 1
    fi
    
    local num=1
    while read ip; do
        [ -z "$ip" ] && continue
        
        # Check if has speed limit
        local limit=""
        if grep -q "^$ip$" "$SPEED_DB" 2>/dev/null; then
            limit="${YELLOW}[LIMITED]${NC}"
        fi
        
        # Check if blocked
        local blocked=""
        if grep -q "^$ip$" "$BLOCK_DB" 2>/dev/null; then
            blocked="${RED}[BLOCKED]${NC}"
        fi
        
        printf "${CYAN}%2d.${NC} %-15s %s %s\n" "$num" "$ip" "$limit" "$blocked"
        ((num++))
    done <<< "$clients"
    
    return 0
}

# ═══════════════════════════════════════════════════
# SPEED LIMIT (SIMPLE VERSION)
# ═══════════════════════════════════════════════════
limit_speed() {
    banner
    echo -e "${CYAN}══════ SPEED LIMIT ══════${NC}\n"
    
    list_clients || return
    
    echo -e "\n${GREEN}Enter device number to limit${NC}"
    echo -e "${YELLOW}Enter 0 to limit ALL devices${NC}"
    echo -e "${RED}Enter 99 to REMOVE all limits${NC}"
    
    read -p $'\n'"Choice: " choice
    
    # Remove all limits
    if [ "$choice" = "99" ]; then
        echo -e "\n${YELLOW}Removing all speed limits...${NC}"
        
        # Clear all tc rules
        su -c "tc qdisc del dev $INTERFACE root" 2>/dev/null
        
        # Clear speed database
        > "$SPEED_DB"
        
        echo -e "${GREEN}[✓] All limits removed${NC}"
        sleep 2
        return
    fi
    
    # Get target IP(s)
    local target_ips=""
    if [ "$choice" = "0" ]; then
        target_ips=$(get_clients)
        echo -e "\n${YELLOW}Limiting ALL devices...${NC}"
    else
        local clients=$(get_clients)
        local num=1
        while read ip; do
            [ -z "$ip" ] && continue
            if [ "$num" = "$choice" ]; then
                target_ips="$ip"
                echo -e "\n${YELLOW}Limiting $ip...${NC}"
                break
            fi
            ((num++))
        done <<< "$clients"
    fi
    
    [ -z "$target_ips" ] && echo -e "${RED}Invalid selection${NC}" && sleep 2 && return
    
    # Simple speed limit using wondershaper method
    find_interface
    
    # Setup basic tc structure
    su -c "tc qdisc del dev $INTERFACE root" 2>/dev/null
    su -c "tc qdisc add dev $INTERFACE root handle 1: htb default 30"
    su -c "tc class add dev $INTERFACE parent 1: classid 1:1 htb rate 100mbit"
    su -c "tc class add dev $INTERFACE parent 1: classid 1:30 htb rate 100mbit"
    
    # Apply limit to each IP
    local class_num=10
    while read ip; do
        [ -z "$ip" ] && continue
        
        # Create class with 50KB/s limit (400kbit)
        su -c "tc class add dev $INTERFACE parent 1:1 classid 1:$class_num htb rate 400kbit"
        
        # Filter traffic to this IP
        su -c "tc filter add dev $INTERFACE protocol ip parent 1:0 prio 1 u32 match ip dst $ip flowid 1:$class_num"
        
        # Save to database
        echo "$ip" >> "$SPEED_DB"
        
        echo -e "${GREEN}[✓] Limited $ip to 50KB/s${NC}"
        
        ((class_num++))
    done <<< "$target_ips"
    
    sleep 2
}

# ═══════════════════════════════════════════════════
# BLOCK DEVICE
# ═══════════════════════════════════════════════════
block_device() {
    banner
    echo -e "${CYAN}══════ BLOCK DEVICE ══════${NC}\n"
    
    list_clients || return
    
    read -p $'\n'"Enter device number to block: " choice
    
    local clients=$(get_clients)
    local num=1
    local target_ip=""
    
    while read ip; do
        [ -z "$ip" ] && continue
        if [ "$num" = "$choice" ]; then
            target_ip="$ip"
            break
        fi
        ((num++))
    done <<< "$clients"
    
    if [ -n "$target_ip" ]; then
        echo -e "\n${YELLOW}Blocking $target_ip...${NC}"
        
        # Block with iptables
        su -c "iptables -A INPUT -s $target_ip -j DROP"
        su -c "iptables -A FORWARD -s $target_ip -j DROP"
        
        # Save to database
        echo "$target_ip" >> "$BLOCK_DB"
        
        echo -e "${GREEN}[✓] Blocked $target_ip${NC}"
    else
        echo -e "${RED}Invalid selection${NC}"
    fi
    
    sleep 2
}

# ═══════════════════════════════════════════════════
# UNBLOCK DEVICE
# ═══════════════════════════════════════════════════
unblock_device() {
    banner
    echo -e "${CYAN}══════ UNBLOCK DEVICE ══════${NC}\n"
    
    if [ ! -s "$BLOCK_DB" ]; then
        echo -e "${RED}No blocked devices${NC}"
        sleep 2
        return
    fi
    
    echo -e "${YELLOW}Blocked Devices:${NC}\n"
    
    local num=1
    while read ip; do
        [ -z "$ip" ] && continue
        printf "${CYAN}%2d.${NC} %s\n" "$num" "$ip"
        ((num++))
    done < "$BLOCK_DB"
    
    read -p $'\n'"Enter device number to unblock: " choice
    
    local num=1
    local target_ip=""
    
    while read ip; do
        [ -z "$ip" ] && continue
        if [ "$num" = "$choice" ]; then
            target_ip="$ip"
            break
        fi
        ((num++))
    done < "$BLOCK_DB"
    
    if [ -n "$target_ip" ]; then
        echo -e "\n${YELLOW}Unblocking $target_ip...${NC}"
        
        # Remove iptables rules
        su -c "iptables -D INPUT -s $target_ip -j DROP" 2>/dev/null
        su -c "iptables -D FORWARD -s $target_ip -j DROP" 2>/dev/null
        
        # Remove from database
        grep -v "^$target_ip$" "$BLOCK_DB" > "$BLOCK_DB.tmp"
        mv "$BLOCK_DB.tmp" "$BLOCK_DB"
        
        echo -e "${GREEN}[✓] Unblocked $target_ip${NC}"
    else
        echo -e "${RED}Invalid selection${NC}"
    fi
    
    sleep 2
}

# ═══════════════════════════════════════════════════
# KICK DEVICE
# ═══════════════════════════════════════════════════
kick_device() {
    banner
    echo -e "${CYAN}══════ KICK DEVICE ══════${NC}\n"
    
    list_clients || return
    
    read -p $'\n'"Enter device number to kick: " choice
    
    local clients=$(get_clients)
    local num=1
    local target_ip=""
    
    while read ip; do
        [ -z "$ip" ] && continue
        if [ "$num" = "$choice" ]; then
            target_ip="$ip"
            break
        fi
        ((num++))
    done <<< "$clients"
    
    if [ -n "$target_ip" ]; then
        echo -e "\n${YELLOW}Kicking $target_ip...${NC}"
        
        find_interface
        
        # Remove from ARP table
        su -c "arp -d $target_ip" 2>/dev/null
        su -c "ip neigh del $target_ip dev $INTERFACE" 2>/dev/null
        
        # Temporarily block for 5 seconds
        su -c "iptables -A INPUT -s $target_ip -j DROP"
        su -c "iptables -A FORWARD -s $target_ip -j DROP"
        
        sleep 5
        
        # Unblock
        su -c "iptables -D INPUT -s $target_ip -j DROP" 2>/dev/null
        su -c "iptables -D FORWARD -s $target_ip -j DROP" 2>/dev/null
        
        echo -e "${GREEN}[✓] Kicked $target_ip${NC}"
    else
        echo -e "${RED}Invalid selection${NC}"
    fi
    
    sleep 2
}

# ═══════════════════════════════════════════════════
# SET TTL
# ═══════════════════════════════════════════════════
set_ttl() {
    banner
    echo -e "${CYAN}══════ TTL SETTINGS ══════${NC}\n"
    
    echo -e "${YELLOW}Current TTL: $(cat /proc/sys/net/ipv4/ip_default_ttl 2>/dev/null || echo Unknown)${NC}\n"
    
    echo -e "${CYAN}1.${NC} Set TTL to 65 (Bypass detection)"
    echo -e "${CYAN}2.${NC} Set TTL to 64 (Default)"
    echo -e "${CYAN}3.${NC} Custom TTL"
    echo -e "${CYAN}0.${NC} Back"
    
    read -p $'\n'"Choice: " choice
    
    case $choice in
        1)
            su -c "echo 65 > /proc/sys/net/ipv4/ip_default_ttl"
            su -c "iptables -t mangle -F POSTROUTING"
            su -c "iptables -t mangle -A POSTROUTING -j TTL --ttl-set 65"
            echo -e "\n${GREEN}[✓] TTL set to 65${NC}"
            ;;
        2)
            su -c "echo 64 > /proc/sys/net/ipv4/ip_default_ttl"
            su -c "iptables -t mangle -F POSTROUTING"
            echo -e "\n${GREEN}[✓] TTL set to 64${NC}"
            ;;
        3)
            read -p "Enter TTL value (1-255): " ttl
            if [[ "$ttl" =~ ^[0-9]+$ ]] && [ "$ttl" -ge 1 ] && [ "$ttl" -le 255 ]; then
                su -c "echo $ttl > /proc/sys/net/ipv4/ip_default_ttl"
                su -c "iptables -t mangle -F POSTROUTING"
                su -c "iptables -t mangle -A POSTROUTING -j TTL --ttl-set $ttl"
                echo -e "\n${GREEN}[✓] TTL set to $ttl${NC}"
            else
                echo -e "\n${RED}Invalid TTL value${NC}"
            fi
            ;;
    esac
    
    sleep 2
}

# ═══════════════════════════════════════════════════
# VIEW STATUS
# ═══════════════════════════════════════════════════
view_status() {
    banner
    echo -e "${CYAN}══════ STATUS ══════${NC}\n"
    
    find_interface
    
    echo -e "${YELLOW}Interface:${NC} $INTERFACE"
    echo -e "${YELLOW}TTL:${NC} $(cat /proc/sys/net/ipv4/ip_default_ttl 2>/dev/null || echo Unknown)"
    echo -e "${YELLOW}IP Forward:${NC} $(cat /proc/sys/net/ipv4/ip_forward 2>/dev/null || echo 0)"
    
    echo -e "\n${CYAN}Connected Devices:${NC}"
    local count=$(get_clients | wc -l)
    echo -e "${GREEN}$count devices connected${NC}"
    
    if [ -s "$SPEED_DB" ]; then
        echo -e "\n${CYAN}Speed Limited:${NC}"
        cat "$SPEED_DB"
    fi
    
    if [ -s "$BLOCK_DB" ]; then
        echo -e "\n${CYAN}Blocked:${NC}"
        cat "$BLOCK_DB"
    fi
    
    read -p $'\n'"Press Enter to continue..."
}

# ═══════════════════════════════════════════════════
# MAIN MENU
# ═══════════════════════════════════════════════════
main_menu() {
    while true; do
        banner
        
        echo -e "${CYAN}1.${NC} View Connected Devices"
        echo -e "${CYAN}2.${NC} Speed Limit (50KB/s)"
        echo -e "${CYAN}3.${NC} Block Device"
        echo -e "${CYAN}4.${NC} Unblock Device"
        echo -e "${CYAN}5.${NC} Kick Device"
        echo -e "${CYAN}6.${NC} TTL Settings"
        echo -e "${CYAN}7.${NC} View Status"
        echo -e "${CYAN}0.${NC} Exit"
        
        read -p $'\n'"Choose: " choice
        
        case $choice in
            1)
                banner
                echo -e "${CYAN}══════ CONNECTED DEVICES ══════${NC}\n"
                list_clients
                read -p $'\n'"Press Enter to continue..."
                ;;
            2) limit_speed ;;
            3) block_device ;;
            4) unblock_device ;;
            5) kick_device ;;
            6) set_ttl ;;
            7) view_status ;;
            0)
                echo -e "\n${CYAN}By: senzore ganteng${NC}\n"
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
# MAIN
# ═══════════════════════════════════════════════════
main() {
    # Create config directory
    mkdir -p "$CONFIG_DIR"
    touch "$SPEED_DB" "$BLOCK_DB"
    
    banner
    echo -e "${CYAN}Initializing...${NC}\n"
    
    check_root
    
    echo -e "${GREEN}[✓] Ready${NC}\n"
    echo -e "${YELLOW}TTL forced to 65 (bypass carrier detection)${NC}"
    
    sleep 2
    
    main_menu
}

# Start
main
