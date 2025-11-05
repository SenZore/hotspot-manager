#!/data/data/com.termux/files/usr/bin/bash

# ═══════════════════════════════════════════════════
# 4G HOTSPOT SPEED MANAGER v4.0 - FIXED DETECTION
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
    echo -e "${W}    4G SPEED MANAGER v4.0${N}"
    echo -e "${C}================================${N}\n"
}

# ═══════════════════════════════════════════════════
# GET INTERFACE - FROM WORKING VERSION
# ═══════════════════════════════════════════════════
get_iface() {
    # Check for active hotspot interface
    for iface in ap0 swlan0 wlan0 wlan1 rmnet_data0 rmnet_data1 rndis0; do
        local ip=$(su -c "ip addr show $iface 2>/dev/null | grep 'inet ' | grep -v '127.0.0.1' | awk '{print \$2}' | cut -d/ -f1")
        if [ -n "$ip" ]; then
            echo "$iface"
            return
        fi
    done
    
    # Fallback
    echo "wlan0"
}

# ═══════════════════════════════════════════════════
# GET CLIENTS - EXACT WORKING METHOD FROM BEFORE
# ═══════════════════════════════════════════════════
get_clients() {
    local all_ips=""
    local iface=$(get_iface)
    
    # Method 1: From /proc/net/arp (MOST RELIABLE)
    local arp_ips=$(su -c "cat /proc/net/arp 2>/dev/null" | grep "$iface" | grep -v "00:00:00:00:00:00" | awk '{print $1}' | grep -E '^[0-9]+\.')
    all_ips="$all_ips $arp_ips"
    
    # Method 2: From ip neigh
    local neigh_ips=$(su -c "ip neigh show 2>/dev/null" | grep -E "REACHABLE|STALE|DELAY" | awk '{print $1}' | grep -E '^[0-9]+\.')
    all_ips="$all_ips $neigh_ips"
    
    # Method 3: From arp command
    local arp_cmd=$(su -c "arp -n 2>/dev/null" | grep -v incomplete | tail -n +2 | awk '{print $1}' | grep -E '^[0-9]+\.')
    all_ips="$all_ips $arp_cmd"
    
    # Method 4: DHCP leases
    local dhcp_ips=$(su -c "cat /data/misc/dhcp/dnsmasq.leases 2>/dev/null | awk '{print \$3}'")
    all_ips="$all_ips $dhcp_ips"
    
    # Remove duplicates and sort
    echo "$all_ips" | tr ' ' '\n' | grep -E '^[0-9]+\.' | sort -u | grep -v '^$'
}

# ═══════════════════════════════════════════════════
# APPLY SPEED - WORKING TC METHOD
# ═══════════════════════════════════════════════════
set_speed() {
    local ip=$1
    local speed=$2
    local iface=$(get_iface)
    
    echo -e "${Y}Setting $ip to ${speed}KB/s...${N}"
    
    if [ "$speed" = "0" ]; then
        # Remove limit
        su -c "tc filter del dev $iface protocol ip parent 1:0 prio 1 2>/dev/null"
        sed -i "/^$ip /d" "$SPEED_DB" 2>/dev/null
        echo -e "${G}Limit removed${N}"
        return
    fi
    
    # Setup TC root if not exists
    su -c "tc qdisc show dev $iface | grep -q htb" || {
        su -c "tc qdisc add dev $iface root handle 1: htb default 30"
        su -c "tc class add dev $iface parent 1: classid 1:1 htb rate 100mbit"
        su -c "tc class add dev $iface parent 1: classid 1:30 htb rate 100mbit"
    }
    
    # Apply limit
    local rate=$((speed * 8))  # KB/s to kbit
    local burst=$((speed * 2))
    local class_id="1:$(echo $ip | cut -d. -f4)"
    
    su -c "tc class add dev $iface parent 1:1 classid $class_id htb rate ${rate}kbit burst ${burst}k"
    su -c "tc filter add dev $iface protocol ip parent 1:0 prio 1 u32 match ip dst $ip flowid $class_id"
    
    # Save to DB
    sed -i "/^$ip /d" "$SPEED_DB" 2>/dev/null
    echo "$ip $speed" >> "$SPEED_DB"
    
    echo -e "${G}Done${N}"
}

# ═══════════════════════════════════════════════════
# SHOW CLIENTS - SIMPLE NO BOXES
# ═══════════════════════════════════════════════════
show_clients() {
    echo -e "${Y}Scanning for devices...${N}"
    
    local clients=$(get_clients)
    
    if [ -z "$clients" ]; then
        echo -e "${R}No devices found${N}"
        echo -e "${Y}Make sure:${N}"
        echo "1. Hotspot is ON"
        echo "2. Devices are connected"
        return 1
    fi
    
    echo -e "\n${C}Connected Devices:${N}"
    echo "------------------------"
    
    local n=1
    echo "$clients" > /tmp/.clients
    
    while read ip; do
        [ -z "$ip" ] && continue
        
        local speed=$(grep "^$ip " "$SPEED_DB" 2>/dev/null | cut -d' ' -f2)
        [ -z "$speed" ] && speed="Unlimited" || speed="${speed}KB/s"
        
        printf "${W}%2d.${N} %-15s [${Y}%s${N}]\n" "$n" "$ip" "$speed"
        ((n++))
    done <<< "$clients"
    
    echo "------------------------"
    echo -e "${G}Total: $((n-1)) devices${N}"
    return 0
}

# ═══════════════════════════════════════════════════
# SPEED CONTROL MENU
# ═══════════════════════════════════════════════════
speed_menu() {
    header
    echo -e "${C}SPEED CONTROL${N}\n"
    
    show_clients || { sleep 2; return; }
    
    echo -e "\n${G}0${N}  = Apply to ALL devices"
    echo -e "${R}99${N} = Remove ALL limits"
    
    read -p $'\n'"Select device: " dev
    
    if [ "$dev" = "99" ]; then
        echo -e "\n${Y}Removing all limits...${N}"
        
        local iface=$(get_iface)
        su -c "tc qdisc del dev $iface root" 2>/dev/null
        su -c "tc qdisc del dev $iface ingress" 2>/dev/null
        
        > "$SPEED_DB"
        
        echo -e "${G}All limits removed${N}"
        sleep 2
        return
    fi
    
    echo -e "\n${C}Speed Options:${N}"
    echo "1. 25 KB/s  (Very Slow)"
    echo "2. 50 KB/s  (Slow)"
    echo "3. 100 KB/s (Limited)"
    echo "4. 200 KB/s (Medium)"
    echo "5. 500 KB/s (Fast)"
    echo "6. Custom speed"
    echo "7. Remove limit"
    
    read -p $'\n'"Choose: " opt
    
    local speed=0
    case $opt in
        1) speed=25 ;;
        2) speed=50 ;;
        3) speed=100 ;;
        4) speed=200 ;;
        5) speed=500 ;;
        6) 
            read -p "Enter KB/s: " speed
            if ! [[ "$speed" =~ ^[0-9]+$ ]]; then
                echo -e "${R}Invalid speed${N}"
                sleep 2
                return
            fi
            ;;
        7) speed=0 ;;
        *) echo -e "${R}Invalid${N}"; sleep 1; return ;;
    esac
    
    if [ "$dev" = "0" ]; then
        # Apply to all devices
        echo -e "\n${Y}Applying to ALL devices...${N}\n"
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
# BLOCK DEVICE
# ═══════════════════════════════════════════════════
block_menu() {
    header
    echo -e "${C}BLOCK DEVICE${N}\n"
    
    show_clients || { sleep 2; return; }
    
    read -p $'\n'"Block which device: " dev
    
    local ip=$(sed -n "${dev}p" /tmp/.clients 2>/dev/null)
    
    if [ -n "$ip" ]; then
        echo -e "\n${Y}Blocking $ip...${N}"
        
        su -c "iptables -I INPUT -s $ip -j DROP"
        su -c "iptables -I FORWARD -s $ip -j DROP"
        su -c "iptables -I FORWARD -d $ip -j DROP"
        
        echo "$ip" >> "$BLOCK_DB"
        echo -e "${G}Device blocked${N}"
    else
        echo -e "${R}Invalid selection${N}"
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
    echo "------------------------"
    
    local n=1
    while read ip; do
        [ -z "$ip" ] && continue
        printf "${W}%2d.${N} %s\n" "$n" "$ip"
        ((n++))
    done < "$BLOCK_DB"
    
    echo "------------------------"
    
    read -p $'\n'"Unblock which: " dev
    
    local ip=$(sed -n "${dev}p" "$BLOCK_DB" 2>/dev/null)
    
    if [ -n "$ip" ]; then
        echo -e "\n${Y}Unblocking $ip...${N}"
        
        su -c "iptables -D INPUT -s $ip -j DROP" 2>/dev/null
        su -c "iptables -D FORWARD -s $ip -j DROP" 2>/dev/null
        su -c "iptables -D FORWARD -d $ip -j DROP" 2>/dev/null
        
        sed -i "/^$ip$/d" "$BLOCK_DB"
        echo -e "${G}Device unblocked${N}"
    else
        echo -e "${R}Invalid selection${N}"
    fi
    
    sleep 2
}

# ═══════════════════════════════════════════════════
# VIEW STATUS
# ═══════════════════════════════════════════════════
view_status() {
    header
    echo -e "${C}SYSTEM STATUS${N}\n"
    
    local iface=$(get_iface)
    local clients_count=$(get_clients | wc -l)
    local limited=$(cat "$SPEED_DB" 2>/dev/null | wc -l)
    local blocked=$(cat "$BLOCK_DB" 2>/dev/null | wc -l)
    
    echo "Interface: ${G}$iface${N}"
    echo "Connected: ${G}$clients_count devices${N}"
    echo "Limited: ${Y}$limited devices${N}"
    echo "Blocked: ${R}$blocked devices${N}"
    echo "TTL: ${G}$(cat /proc/sys/net/ipv4/ip_default_ttl)${N}"
    
    if [ -s "$SPEED_DB" ]; then
        echo -e "\n${C}Speed Limits:${N}"
        echo "------------------------"
        while read line; do
            [ -z "$line" ] && continue
            local ip=$(echo $line | cut -d' ' -f1)
            local speed=$(echo $line | cut -d' ' -f2)
            echo "$ip = ${speed}KB/s"
        done < "$SPEED_DB"
    fi
    
    read -p $'\nPress Enter...'
}

# ═══════════════════════════════════════════════════
# MONITOR
# ═══════════════════════════════════════════════════
monitor() {
    header
    echo -e "${C}BANDWIDTH MONITOR${N}\n"
    
    local iface=$(get_iface)
    echo "Interface: $iface"
    echo -e "${Y}Press Ctrl+C to stop${N}\n"
    
    while true; do
        local rx1=$(cat /sys/class/net/$iface/statistics/rx_bytes 2>/dev/null || echo 0)
        local tx1=$(cat /sys/class/net/$iface/statistics/tx_bytes 2>/dev/null || echo 0)
        
        sleep 1
        
        local rx2=$(cat /sys/class/net/$iface/statistics/rx_bytes 2>/dev/null || echo 0)
        local tx2=$(cat /sys/class/net/$iface/statistics/tx_bytes 2>/dev/null || echo 0)
        
        local rx_rate=$(( (rx2 - rx1) / 1024 ))
        local tx_rate=$(( (tx2 - tx1) / 1024 ))
        
        printf "\rDown: ${G}%d KB/s${N}  Up: ${R}%d KB/s${N}  " $rx_rate $tx_rate
    done
}

# ═══════════════════════════════════════════════════
# RESET ALL
# ═══════════════════════════════════════════════════
reset_all() {
    header
    echo -e "${C}RESET ALL${N}\n"
    
    echo -e "${Y}Resetting everything...${N}"
    
    local iface=$(get_iface)
    
    # Clear TC
    su -c "tc qdisc del dev $iface root" 2>/dev/null
    su -c "tc qdisc del dev $iface ingress" 2>/dev/null
    
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
    
    echo -e "${G}Everything reset!${N}"
    sleep 2
}

# ═══════════════════════════════════════════════════
# MAIN MENU
# ═══════════════════════════════════════════════════
menu() {
    while true; do
        header
        
        local clients_count=$(get_clients | wc -l)
        echo "Connected: ${G}$clients_count${N} devices"
        
        local limited=$(cat "$SPEED_DB" 2>/dev/null | wc -l)
        [ $limited -gt 0 ] && echo "Limited: ${Y}$limited${N} devices"
        
        echo ""
        echo "1. Speed Control"
        echo "2. Block Device"
        echo "3. Unblock Device"
        echo "4. View Status"
        echo "5. Monitor Speed"
        echo "6. Reset All"
        echo "0. Exit"
        
        read -p $'\nChoice: ' opt
        
        case $opt in
            1) speed_menu ;;
            2) block_menu ;;
            3) unblock_menu ;;
            4) view_status ;;
            5) monitor ;;
            6) reset_all ;;
            0) 
                echo -e "\n${C}By: senzore ganteng${N}\n"
                exit 0
                ;;
        esac
    done
}

# ═══════════════════════════════════════════════════
# MAIN START
# ═══════════════════════════════════════════════════
main() {
    header
    
    echo -e "${Y}Checking root...${N}"
    
    if ! su -c "id" &>/dev/null; then
        echo -e "${R}Root access required!${N}"
        echo -e "${Y}Please grant root permission${N}"
        exit 1
    fi
    
    echo -e "${G}Root OK${N}"
    echo -e "${G}TTL: $(cat /proc/sys/net/ipv4/ip_default_ttl)${N}"
    echo -e "${G}Ready!${N}\n"
    
    sleep 1
    
    menu
}

# Run
main
