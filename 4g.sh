#!/data/data/com.termux/files/usr/bin/bash

# ═══════════════════════════════════════════════════
# 4G HOTSPOT SPEED MANAGER v3.0 - MOBILE OPTIMIZED
# By: senzore ganteng
# Save as: ./4g.sh
# ═══════════════════════════════════════════════════

# Simple colors
R='\e[1;31m'; G='\e[1;32m'; Y='\e[1;33m'; C='\e[1;36m'; W='\e[1;37m'; N='\e[0m'

# Config
DATA_DIR="$HOME/.4g_data"
SPEED_DB="$DATA_DIR/speeds.db"
BLOCK_DB="$DATA_DIR/blocked.db"

# Create dirs
mkdir -p "$DATA_DIR" 2>/dev/null
touch "$SPEED_DB" "$BLOCK_DB" 2>/dev/null

# ═══════════════════════════════════════════════════
# SIMPLE HEADER - NO ASCII
# ═══════════════════════════════════════════════════
header() {
    clear
    echo -e "${C}================================${N}"
    echo -e "${W}    4G SPEED MANAGER v3.0${N}"
    echo -e "${C}================================${N}\n"
}

# ═══════════════════════════════════════════════════
# GET INTERFACE - SIMPLIFIED
# ═══════════════════════════════════════════════════
get_iface() {
    # Try common hotspot interfaces
    for i in ap0 swlan0 wlan0; do
        if su -c "ip link show $i 2>/dev/null | grep -q UP"; then
            echo "$i"
            return
        fi
    done
    echo "wlan0"
}

# ═══════════════════════════════════════════════════
# GET CLIENTS - SIMPLIFIED
# ═══════════════════════════════════════════════════
get_clients() {
    su -c "arp -n 2>/dev/null | grep -v incomplete | tail -n +2 | awk '{print \$1}' | grep -E '^[0-9]+\.'" 2>/dev/null
}

# ═══════════════════════════════════════════════════
# APPLY SPEED - WORKING METHOD
# ═══════════════════════════════════════════════════
set_speed() {
    local ip=$1
    local speed=$2
    local iface=$(get_iface)
    
    echo -e "${Y}Setting $ip to ${speed}KB/s...${N}"
    
    # Clear old rules
    su -c "iptables -D FORWARD -s $ip -j ACCEPT" 2>/dev/null
    su -c "iptables -D FORWARD -d $ip -j ACCEPT" 2>/dev/null
    
    if [ "$speed" = "0" ]; then
        # Remove limit
        sed -i "/^$ip /d" "$SPEED_DB" 2>/dev/null
        echo -e "${G}Limit removed${N}"
        return
    fi
    
    # Method 1: Simple iptables rate limiting
    su -c "iptables -I FORWARD -s $ip -m limit --limit ${speed}/s --limit-burst $((speed*2)) -j ACCEPT"
    su -c "iptables -I FORWARD -d $ip -m limit --limit ${speed}/s --limit-burst $((speed*2)) -j ACCEPT"
    su -c "iptables -A FORWARD -s $ip -j DROP"
    su -c "iptables -A FORWARD -d $ip -j DROP"
    
    # Save to DB
    sed -i "/^$ip /d" "$SPEED_DB" 2>/dev/null
    echo "$ip $speed" >> "$SPEED_DB"
    
    echo -e "${G}Done${N}"
}

# ═══════════════════════════════════════════════════
# SHOW CLIENTS - NO ASCII BOXES
# ═══════════════════════════════════════════════════
show_clients() {
    echo -e "${Y}Connected Devices:${N}"
    echo -e "${C}----------------${N}"
    
    local clients=$(get_clients)
    
    if [ -z "$clients" ]; then
        echo -e "${R}No devices found${N}"
        return 1
    fi
    
    local n=1
    echo "$clients" > /tmp/.clients
    
    while read ip; do
        [ -z "$ip" ] && continue
        
        local speed=$(grep "^$ip " "$SPEED_DB" 2>/dev/null | cut -d' ' -f2)
        [ -z "$speed" ] && speed="Unlimited" || speed="${speed}KB/s"
        
        echo -e "${W}$n.${N} $ip [$speed]"
        ((n++))
    done <<< "$clients"
    
    echo -e "${C}----------------${N}"
    return 0
}

# ═══════════════════════════════════════════════════
# SPEED CONTROL - SIMPLIFIED
# ═══════════════════════════════════════════════════
speed_menu() {
    header
    echo -e "${C}SPEED CONTROL${N}\n"
    
    show_clients || { sleep 2; return; }
    
    echo -e "\n${G}0${N} = ALL devices"
    echo -e "${R}99${N} = Remove ALL limits"
    
    read -p "Select device: " dev
    
    if [ "$dev" = "99" ]; then
        echo -e "\n${Y}Removing all limits...${N}"
        
        # Clear all forward rules
        su -c "iptables -F FORWARD" 2>/dev/null
        su -c "iptables -P FORWARD ACCEPT" 2>/dev/null
        
        > "$SPEED_DB"
        
        echo -e "${G}All limits removed${N}"
        sleep 2
        return
    fi
    
    echo -e "\n${C}Speed Options:${N}"
    echo -e "1. 25 KB/s"
    echo -e "2. 50 KB/s"
    echo -e "3. 100 KB/s"
    echo -e "4. 200 KB/s"
    echo -e "5. 500 KB/s"
    echo -e "6. Custom"
    echo -e "7. Unlimited"
    
    read -p "Choose: " opt
    
    local speed=0
    case $opt in
        1) speed=25 ;;
        2) speed=50 ;;
        3) speed=100 ;;
        4) speed=200 ;;
        5) speed=500 ;;
        6) read -p "Enter KB/s: " speed ;;
        7) speed=0 ;;
        *) echo -e "${R}Invalid${N}"; sleep 1; return ;;
    esac
    
    if [ "$dev" = "0" ]; then
        # All devices
        local clients=$(get_clients)
        while read ip; do
            [ -z "$ip" ] && continue
            set_speed "$ip" "$speed"
        done <<< "$clients"
    else
        # Single device
        local ip=$(sed -n "${dev}p" /tmp/.clients 2>/dev/null)
        if [ -n "$ip" ]; then
            set_speed "$ip" "$speed"
        else
            echo -e "${R}Invalid device${N}"
        fi
    fi
    
    sleep 2
}

# ═══════════════════════════════════════════════════
# BLOCK DEVICE - SIMPLE
# ═══════════════════════════════════════════════════
block_menu() {
    header
    echo -e "${C}BLOCK DEVICE${N}\n"
    
    show_clients || { sleep 2; return; }
    
    read -p "Block which device: " dev
    
    local ip=$(sed -n "${dev}p" /tmp/.clients 2>/dev/null)
    
    if [ -n "$ip" ]; then
        echo -e "\n${Y}Blocking $ip...${N}"
        
        su -c "iptables -I INPUT -s $ip -j DROP"
        su -c "iptables -I FORWARD -s $ip -j DROP"
        
        echo "$ip" >> "$BLOCK_DB"
        echo -e "${G}Blocked${N}"
    else
        echo -e "${R}Invalid${N}"
    fi
    
    sleep 2
}

# ═══════════════════════════════════════════════════
# UNBLOCK DEVICE
# ═══════════════════════════════════════════════════
unblock_menu() {
    header
    echo -e "${C}UNBLOCK DEVICE${N}\n"
    
    if [ ! -s "$BLOCK_DB" ]; then
        echo -e "${R}No blocked devices${N}"
        sleep 2
        return
    fi
    
    echo -e "${Y}Blocked Devices:${N}"
    echo -e "${C}----------------${N}"
    
    local n=1
    while read ip; do
        [ -z "$ip" ] && continue
        echo -e "${W}$n.${N} $ip"
        ((n++))
    done < "$BLOCK_DB"
    
    echo -e "${C}----------------${N}"
    
    read -p "Unblock which: " dev
    
    local ip=$(sed -n "${dev}p" "$BLOCK_DB" 2>/dev/null)
    
    if [ -n "$ip" ]; then
        echo -e "\n${Y}Unblocking $ip...${N}"
        
        su -c "iptables -D INPUT -s $ip -j DROP" 2>/dev/null
        su -c "iptables -D FORWARD -s $ip -j DROP" 2>/dev/null
        
        sed -i "/^$ip$/d" "$BLOCK_DB"
        echo -e "${G}Unblocked${N}"
    else
        echo -e "${R}Invalid${N}"
    fi
    
    sleep 2
}

# ═══════════════════════════════════════════════════
# VIEW STATUS - SIMPLE
# ═══════════════════════════════════════════════════
view_status() {
    header
    echo -e "${C}STATUS${N}\n"
    
    local iface=$(get_iface)
    local clients=$(get_clients | wc -l)
    local limited=$(cat "$SPEED_DB" 2>/dev/null | wc -l)
    local blocked=$(cat "$BLOCK_DB" 2>/dev/null | wc -l)
    
    echo -e "Interface: ${G}$iface${N}"
    echo -e "Connected: ${G}$clients devices${N}"
    echo -e "Limited: ${Y}$limited devices${N}"
    echo -e "Blocked: ${R}$blocked devices${N}"
    echo -e "TTL: ${G}$(cat /proc/sys/net/ipv4/ip_default_ttl)${N}"
    
    if [ -s "$SPEED_DB" ]; then
        echo -e "\n${C}Speed Limits:${N}"
        while read line; do
            [ -z "$line" ] && continue
            local ip=$(echo $line | cut -d' ' -f1)
            local speed=$(echo $line | cut -d' ' -f2)
            echo "  $ip = ${speed}KB/s"
        done < "$SPEED_DB"
    fi
    
    read -p $'\nPress Enter...'
}

# ═══════════════════════════════════════════════════
# MONITOR - SIMPLE
# ═══════════════════════════════════════════════════
monitor() {
    header
    echo -e "${C}BANDWIDTH MONITOR${N}\n"
    
    local iface=$(get_iface)
    echo -e "Interface: $iface"
    echo -e "${Y}Press Ctrl+C to stop${N}\n"
    
    while true; do
        local rx1=$(cat /sys/class/net/$iface/statistics/rx_bytes 2>/dev/null)
        local tx1=$(cat /sys/class/net/$iface/statistics/tx_bytes 2>/dev/null)
        
        sleep 1
        
        local rx2=$(cat /sys/class/net/$iface/statistics/rx_bytes 2>/dev/null)
        local tx2=$(cat /sys/class/net/$iface/statistics/tx_bytes 2>/dev/null)
        
        local rx_rate=$(( (rx2 - rx1) / 1024 ))
        local tx_rate=$(( (tx2 - tx1) / 1024 ))
        
        printf "\rDown: ${G}%d KB/s${N}  Up: ${R}%d KB/s${N}  " $rx_rate $tx_rate
    done
}

# ═══════════════════════════════════════════════════
# FIX EVERYTHING
# ═══════════════════════════════════════════════════
fix_all() {
    header
    echo -e "${C}FIX ALL${N}\n"
    
    echo -e "${Y}Resetting everything...${N}"
    
    # Clear iptables
    su -c "iptables -F" 2>/dev/null
    su -c "iptables -P INPUT ACCEPT" 2>/dev/null
    su -c "iptables -P FORWARD ACCEPT" 2>/dev/null
    su -c "iptables -P OUTPUT ACCEPT" 2>/dev/null
    
    # Enable forwarding
    su -c "echo 1 > /proc/sys/net/ipv4/ip_forward" 2>/dev/null
    
    # Clear databases
    > "$SPEED_DB"
    > "$BLOCK_DB"
    
    echo -e "${G}Fixed!${N}"
    sleep 2
}

# ═══════════════════════════════════════════════════
# MAIN MENU - SIMPLE
# ═══════════════════════════════════════════════════
menu() {
    while true; do
        header
        
        local clients=$(get_clients | wc -l)
        echo -e "Connected: ${G}$clients${N} devices\n"
        
        echo "1. Speed Control"
        echo "2. Block Device"
        echo "3. Unblock Device"
        echo "4. View Status"
        echo "5. Monitor"
        echo "6. Fix All"
        echo "0. Exit"
        
        read -p $'\nChoice: ' opt
        
        case $opt in
            1) speed_menu ;;
            2) block_menu ;;
            3) unblock_menu ;;
            4) view_status ;;
            5) monitor ;;
            6) fix_all ;;
            0) 
                echo -e "\n${C}By: senzore ganteng${N}\n"
                exit 0
                ;;
        esac
    done
}

# ═══════════════════════════════════════════════════
# START
# ═══════════════════════════════════════════════════
main() {
    header
    
    echo -e "${Y}Checking root...${N}"
    
    if ! su -c "id" &>/dev/null; then
        echo -e "${R}Root required!${N}"
        exit 1
    fi
    
    echo -e "${G}Root OK${N}"
    echo -e "${G}Ready!${N}\n"
    
    sleep 1
    
    menu
}

# Run
main
