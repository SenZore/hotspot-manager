#!/data/data/com.termux/files/usr/bin/bash

# ═══════════════════════════════════════════════════
# 4G HOTSPOT SPEED MANAGER v2.0 - CUSTOM SPEEDS
# By: senzore ganteng
# Save as: ./4g.sh
# ═══════════════════════════════════════════════════

# Quick colors
R='\e[1;31m'; G='\e[1;32m'; Y='\e[1;33m'; B='\e[1;34m'; C='\e[1;36m'; W='\e[1;37m'; N='\e[0m'

# Auto setup on first run
FIRST_RUN="$HOME/.4g_installed"
DATA_DIR="$HOME/.4g_data"
SPEED_DB="$DATA_DIR/speeds.db"

# ═══════════════════════════════════════════════════
# AUTO INSTALLER
# ═══════════════════════════════════════════════════
auto_install() {
    if [ ! -f "$FIRST_RUN" ]; then
        clear
        echo -e "${C}╔═══════════════════════════════════════╗${N}"
        echo -e "${C}║     4G SPEED MANAGER - INSTALLER     ║${N}"
        echo -e "${C}╚═══════════════════════════════════════╝${N}\n"
        
        echo -e "${Y}[*] First run detected, installing...${N}"
        
        # Create directories
        mkdir -p "$DATA_DIR"
        touch "$SPEED_DB"
        
        # Install required binaries if missing
        echo -e "${Y}[*] Checking tools...${N}"
        
        # Check for basic tools
        for tool in iptables tc ip arp bc; do
            if ! command -v $tool &>/dev/null; then
                echo -e "${Y}Installing $tool...${N}"
                pkg install -y root-repo &>/dev/null
                pkg install -y iproute2 iptables net-tools bc &>/dev/null
            fi
        done
        
        # Make script executable
        chmod +x "$0"
        
        # Create shortcut
        echo -e "${Y}[*] Creating shortcut...${N}"
        ln -sf "$PWD/4g.sh" "$PREFIX/bin/4g" 2>/dev/null
        
        # Mark as installed
        touch "$FIRST_RUN"
        
        echo -e "${G}[✓] Installation complete!${N}"
        echo -e "${G}[✓] You can now run: ${W}4g${N}"
        sleep 2
    fi
}

# ═══════════════════════════════════════════════════
# HEADER
# ═══════════════════════════════════════════════════
header() {
    clear
    echo -e "${B}╔═══════════════════════════════════════╗${N}"
    echo -e "${B}║${W}    4G SPEED MANAGER v2.0 CUSTOM${B}     ║${N}"
    echo -e "${B}╚═══════════════════════════════════════╝${N}\n"
}

# ═══════════════════════════════════════════════════
# GET INTERFACE
# ═══════════════════════════════════════════════════
get_iface() {
    local iface=$(su -c "ip route | grep default | head -1 | awk '{for(i=1;i<=NF;i++) if(\$i==\"dev\") print \$(i+1)}'" 2>/dev/null)
    
    if [ -z "$iface" ]; then
        iface=$(su -c "ip addr | grep 'inet 192.168' | grep -E '\.1/|\.254/' | head -1 | awk '{print \$NF}'" 2>/dev/null)
    fi
    
    [ -z "$iface" ] && iface="wlan0"
    echo "$iface"
}

# ═══════════════════════════════════════════════════
# FIND CLIENTS - WITH NAMES
# ═══════════════════════════════════════════════════
scan_clients() {
    {
        su -c "cat /proc/net/arp 2>/dev/null | awk 'NR>1 && \$1 ~ /^[0-9]+\./ && \$3 != \"0x0\" {print \$1}'"
        su -c "ip neigh show | grep -E 'REACHABLE|STALE' | awk '{print \$1}' | grep -E '^[0-9]+\.'"
    } 2>/dev/null | sort -u | grep -v '^$'
}

# ═══════════════════════════════════════════════════
# GET CLIENT NAME FROM DATABASE
# ═══════════════════════════════════════════════════
get_client_name() {
    local ip=$1
    local name=$(grep "^$ip|" "$DATA_DIR/names.db" 2>/dev/null | cut -d'|' -f2)
    [ -z "$name" ] && name="Device"
    echo "$name"
}

# ═══════════════════════════════════════════════════
# SET CLIENT NAME
# ═══════════════════════════════════════════════════
set_client_name() {
    local ip=$1
    local name=$2
    
    # Remove old entry
    sed -i "/^$ip|/d" "$DATA_DIR/names.db" 2>/dev/null
    
    # Add new name
    echo "$ip|$name" >> "$DATA_DIR/names.db"
}

# ═══════════════════════════════════════════════════
# GET CURRENT SPEED LIMIT
# ═══════════════════════════════════════════════════
get_speed_limit() {
    local ip=$1
    local speed=$(grep "^$ip " "$SPEED_DB" 2>/dev/null | cut -d' ' -f2)
    [ -z "$speed" ] && speed="Unlimited"
    echo "$speed"
}

# ═══════════════════════════════════════════════════
# APPLY CUSTOM SPEED TO CLIENT
# ═══════════════════════════════════════════════════
apply_speed() {
    local ip=$1
    local speed_kb=$2
    local iface=$(get_iface)
    
    echo -e "${Y}Setting $ip to ${speed_kb} KB/s...${N}"
    
    # Remove old rules
    su -c "tc filter del dev $iface protocol ip parent 1: prio 1 u32 match ip dst $ip 2>/dev/null"
    su -c "tc filter del dev $iface parent ffff: protocol ip prio 1 u32 match ip src $ip 2>/dev/null"
    
    # Remove from speed database if unlimited
    if [ "$speed_kb" = "0" ] || [ "$speed_kb" = "unlimited" ]; then
        sed -i "/^$ip /d" "$SPEED_DB" 2>/dev/null
        echo -e "${G}[✓] Speed limit removed for $ip${N}"
        return
    fi
    
    # Setup TC root if needed
    su -c "tc qdisc show dev $iface | grep -q 'htb 1:' || tc qdisc add dev $iface root handle 1: htb default 999"
    su -c "tc class show dev $iface | grep -q '1:1' || tc class add dev $iface parent 1: classid 1:1 htb rate 1000mbit"
    su -c "tc class show dev $iface | grep -q '1:999' || tc class add dev $iface parent 1:1 classid 1:999 htb rate 1000mbit"
    
    # Setup ingress
    su -c "tc qdisc show dev $iface | grep -q 'ingress' || tc qdisc add dev $iface handle ffff: ingress"
    
    # Calculate values
    local rate_kbit=$((speed_kb * 8))
    local burst_kb=$((speed_kb * 2))
    local last_octet=$(echo $ip | cut -d. -f4)
    local class_id="1:$last_octet"
    
    # Create class for this IP
    su -c "tc class del dev $iface parent 1:1 classid $class_id 2>/dev/null"
    su -c "tc class add dev $iface parent 1:1 classid $class_id htb rate ${rate_kbit}kbit burst ${burst_kb}k cburst ${burst_kb}k"
    
    # Add queue discipline
    su -c "tc qdisc add dev $iface parent $class_id handle $last_octet: sfq perturb 10 2>/dev/null"
    
    # Filter download TO client
    su -c "tc filter add dev $iface protocol ip parent 1: prio 1 u32 match ip dst $ip flowid $class_id"
    
    # Police upload FROM client
    su -c "tc filter add dev $iface parent ffff: protocol ip prio 1 u32 match ip src $ip police rate ${rate_kbit}kbit burst ${burst_kb}k drop flowid :1"
    
    # Save to database
    sed -i "/^$ip /d" "$SPEED_DB" 2>/dev/null
    echo "$ip $speed_kb" >> "$SPEED_DB"
    
    echo -e "${G}[✓] Speed set to ${speed_kb} KB/s${N}"
}

# ═══════════════════════════════════════════════════
# INDIVIDUAL CLIENT SPEED MENU
# ═══════════════════════════════════════════════════
individual_speed() {
    header
    echo -e "${C}[INDIVIDUAL SPEED CONTROL]${N}\n"
    
    local clients=$(scan_clients)
    
    if [ -z "$clients" ]; then
        echo -e "${R}No devices connected!${N}"
        sleep 2
        return
    fi
    
    # Show clients with current speeds
    echo -e "${Y}Connected devices:${N}"
    echo -e "${C}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${N}"
    
    local i=1
    echo "$clients" > /tmp/.clients
    
    while read ip; do
        local name=$(get_client_name "$ip")
        local current_speed=$(get_speed_limit "$ip")
        
        printf "${W}%2d.${N} %-15s │ %-12s │ ${Y}%s KB/s${N}\n" "$i" "$ip" "$name" "$current_speed"
        ((i++))
    done <<< "$clients"
    
    echo -e "${C}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${N}"
    
    read -p $'\n'"Select device [1-$((i-1))]: " device
    
    local target=$(sed -n "${device}p" /tmp/.clients)
    
    if [ -z "$target" ]; then
        echo -e "${R}Invalid selection!${N}"
        sleep 2
        return
    fi
    
    local name=$(get_client_name "$target")
    
    echo -e "\n${C}Selected: $target ($name)${N}"
    echo -e "${Y}Current speed: $(get_speed_limit "$target") KB/s${N}\n"
    
    echo -e "${G}Speed Options:${N}"
    echo -e "${W}1.${N} Custom speed (enter KB/s)"
    echo -e "${W}2.${N} 25 KB/s   (200 kbps - Very Slow)"
    echo -e "${W}3.${N} 50 KB/s   (400 kbps - Slow)"
    echo -e "${W}4.${N} 100 KB/s  (800 kbps - Limited)"
    echo -e "${W}5.${N} 200 KB/s  (1.6 Mbps - Medium)"
    echo -e "${W}6.${N} 500 KB/s  (4 Mbps - Fast)"
    echo -e "${W}7.${N} 1000 KB/s (8 Mbps - Very Fast)"
    echo -e "${W}8.${N} Unlimited (Remove limit)"
    echo -e "${W}9.${N} Set device name"
    
    read -p $'\n'"Choose option: " opt
    
    case $opt in
        1)
            read -p "Enter speed in KB/s: " custom_speed
            if [[ "$custom_speed" =~ ^[0-9]+$ ]]; then
                apply_speed "$target" "$custom_speed"
            else
                echo -e "${R}Invalid speed!${N}"
            fi
            ;;
        2) apply_speed "$target" 25 ;;
        3) apply_speed "$target" 50 ;;
        4) apply_speed "$target" 100 ;;
        5) apply_speed "$target" 200 ;;
        6) apply_speed "$target" 500 ;;
        7) apply_speed "$target" 1000 ;;
        8) apply_speed "$target" 0 ;;
        9)
            read -p "Enter name for this device: " new_name
            set_client_name "$target" "$new_name"
            echo -e "${G}[✓] Name set to: $new_name${N}"
            ;;
        *)
            echo -e "${R}Invalid option!${N}"
            ;;
    esac
    
    sleep 2
}

# ═══════════════════════════════════════════════════
# SET SPEED FOR ALL CLIENTS
# ═══════════════════════════════════════════════════
all_clients_speed() {
    header
    echo -e "${C}[ALL CLIENTS SPEED CONTROL]${N}\n"
    
    local clients=$(scan_clients)
    
    if [ -z "$clients" ]; then
        echo -e "${R}No devices connected!${N}"
        sleep 2
        return
    fi
    
    local count=$(echo "$clients" | wc -l)
    echo -e "${Y}Found $count devices${N}\n"
    
    echo -e "${G}Speed Options for ALL devices:${N}"
    echo -e "${W}1.${N} Custom speed (enter KB/s)"
    echo -e "${W}2.${N} 25 KB/s   (Very Slow)"
    echo -e "${W}3.${N} 50 KB/s   (Slow)"
    echo -e "${W}4.${N} 100 KB/s  (Limited)"
    echo -e "${W}5.${N} 200 KB/s  (Medium)"
    echo -e "${W}6.${N} 500 KB/s  (Fast)"
    echo -e "${W}7.${N} 1000 KB/s (Very Fast)"
    echo -e "${W}8.${N} Remove ALL limits"
    
    read -p $'\n'"Choose option: " opt
    
    local speed=0
    
    case $opt in
        1)
            read -p "Enter speed in KB/s for ALL devices: " speed
            if ! [[ "$speed" =~ ^[0-9]+$ ]]; then
                echo -e "${R}Invalid speed!${N}"
                sleep 2
                return
            fi
            ;;
        2) speed=25 ;;
        3) speed=50 ;;
        4) speed=100 ;;
        5) speed=200 ;;
        6) speed=500 ;;
        7) speed=1000 ;;
        8) speed=0 ;;
        *)
            echo -e "${R}Invalid option!${N}"
            sleep 2
            return
            ;;
    esac
    
    echo -e "\n${Y}Applying speed to ALL devices...${N}\n"
    
    while read ip; do
        [ -z "$ip" ] && continue
        apply_speed "$ip" "$speed"
    done <<< "$clients"
    
    echo -e "\n${G}[✓] Speed applied to ALL devices!${N}"
    sleep 2
}

# ═══════════════════════════════════════════════════
# VIEW ALL CLIENTS WITH SPEEDS
# ═══════════════════════════════════════════════════
view_all_speeds() {
    header
    echo -e "${C}[CLIENT SPEED STATUS]${N}\n"
    
    local clients=$(scan_clients)
    
    if [ -z "$clients" ]; then
        echo -e "${R}No devices connected!${N}"
        sleep 2
        return
    fi
    
    echo -e "${Y}╔═══════════════════════════════════════════════════════════╗${N}"
    echo -e "${Y}║                    CONNECTED DEVICES                     ║${N}"
    echo -e "${Y}╠═══╦════════════════╦══════════════╦═════════════════════╣${N}"
    echo -e "${Y}║ # ║       IP       ║     Name     ║    Speed Limit      ║${N}"
    echo -e "${Y}╠═══╬════════════════╬══════════════╬═════════════════════╣${N}"
    
    local i=1
    while read ip; do
        local name=$(get_client_name "$ip")
        local speed=$(get_speed_limit "$ip")
        
        [ "$speed" = "Unlimited" ] && display_speed="${G}Unlimited${N}" || display_speed="${R}${speed} KB/s${N}"
        
        printf "${Y}║${N}%2d ${Y}║${N} %-14s ${Y}║${N} %-12s ${Y}║${N} %-19s ${Y}║${N}\n" "$i" "$ip" "$name" "$display_speed"
        ((i++))
    done <<< "$clients"
    
    echo -e "${Y}╚═══╩════════════════╩══════════════╩═════════════════════╝${N}"
    
    echo -e "\n${C}Total devices: $((i-1))${N}"
    
    read -p $'\n'"Press Enter to continue..."
}

# ═══════════════════════════════════════════════════
# REMOVE ALL LIMITS
# ═══════════════════════════════════════════════════
remove_all_limits() {
    header
    echo -e "${C}[REMOVE ALL LIMITS]${N}\n"
    
    echo -e "${Y}Removing all speed limits...${N}"
    
    local iface=$(get_iface)
    
    # Clear TC completely
    su -c "tc qdisc del dev $iface root 2>/dev/null"
    su -c "tc qdisc del dev $iface ingress 2>/dev/null"
    
    # Clear speed database
    > "$SPEED_DB"
    
    echo -e "${G}[✓] All speed limits removed!${N}"
    echo -e "${G}[✓] All devices now have unlimited speed${N}"
    
    sleep 2
}

# ═══════════════════════════════════════════════════
# BLOCK DEVICE
# ═══════════════════════════════════════════════════
block_menu() {
    header
    echo -e "${C}[BLOCK DEVICE]${N}\n"
    
    local clients=$(scan_clients)
    
    if [ -z "$clients" ]; then
        echo -e "${R}No devices!${N}"
        sleep 2
        return
    fi
    
    echo -e "${Y}Select device to block:${N}"
    local i=1
    echo "$clients" > /tmp/.clients
    
    while read ip; do
        local name=$(get_client_name "$ip")
        printf "${W}%2d.${N} %-15s │ %s\n" "$i" "$ip" "$name"
        ((i++))
    done <<< "$clients"
    
    read -p $'\n'"Block which? " num
    
    local target=$(sed -n "${num}p" /tmp/.clients)
    
    if [ -n "$target" ]; then
        echo -e "\n${Y}Blocking $target...${N}"
        
        # Complete block
        su -c "iptables -I INPUT -s $target -j REJECT --reject-with icmp-host-prohibited"
        su -c "iptables -I FORWARD -s $target -j REJECT --reject-with icmp-host-prohibited"
        su -c "iptables -I FORWARD -d $target -j REJECT --reject-with icmp-host-prohibited"
        
        # Save to blocked list
        echo "$target" >> "$DATA_DIR/blocked"
        
        echo -e "${G}[✓] Device blocked!${N}"
    fi
    
    sleep 2
}

# ═══════════════════════════════════════════════════
# SPEED MENU - MAIN
# ═══════════════════════════════════════════════════
speed_control_menu() {
    while true; do
        header
        echo -e "${C}[SPEED CONTROL CENTER]${N}\n"
        
        local clients=$(scan_clients | wc -l)
        echo -e "${G}Connected devices: $clients${N}\n"
        
        echo -e "${W}1.${N} Set speed for INDIVIDUAL device"
        echo -e "${W}2.${N} Set speed for ALL devices" 
        echo -e "${W}3.${N} View all device speeds"
        echo -e "${W}4.${N} Remove ALL speed limits"
        echo -e "${W}0.${N} Back"
        
        read -p $'\n'"Choose: " opt
        
        case $opt in
            1) individual_speed ;;
            2) all_clients_speed ;;
            3) view_all_speeds ;;
            4) remove_all_limits ;;
            0) break ;;
        esac
    done
}

# ═══════════════════════════════════════════════════
# MONITOR
# ═══════════════════════════════════════════════════
monitor() {
    header
    echo -e "${C}[BANDWIDTH MONITOR]${N}\n"
    
    local iface=$(get_iface)
    echo -e "${Y}Interface: $iface${N}"
    echo -e "${Y}Press Ctrl+C to exit${N}\n"
    
    echo -e "${C}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${N}"
    
    while true; do
        local rx1=$(cat /sys/class/net/$iface/statistics/rx_bytes 2>/dev/null || echo 0)
        local tx1=$(cat /sys/class/net/$iface/statistics/tx_bytes 2>/dev/null || echo 0)
        
        sleep 1
        
        local rx2=$(cat /sys/class/net/$iface/statistics/rx_bytes 2>/dev/null || echo 0)
        local tx2=$(cat /sys/class/net/$iface/statistics/tx_bytes 2>/dev/null || echo 0)
        
        local rx_rate=$(( (rx2 - rx1) / 1024 ))
        local tx_rate=$(( (tx2 - tx1) / 1024 ))
        
        # Convert to Mbps if > 1024 KB/s
        local rx_display="$rx_rate KB/s"
        local tx_display="$tx_rate KB/s"
        
        if [ $rx_rate -gt 1024 ]; then
            rx_display="$(echo "scale=1; $rx_rate/1024" | bc) MB/s"
        fi
        
        if [ $tx_rate -gt 1024 ]; then
            tx_display="$(echo "scale=1; $tx_rate/1024" | bc) MB/s"
        fi
        
        printf "\r${G}↓ Download:${N} %-10s  ${R}↑ Upload:${N} %-10s" "$rx_display" "$tx_display"
    done
}

# ═══════════════════════════════════════════════════
# MAIN MENU
# ═══════════════════════════════════════════════════
main_menu() {
    while true; do
        header
        
        local clients=$(scan_clients | wc -l)
        local limited=$(cat "$SPEED_DB" 2>/dev/null | wc -l)
        
        echo -e "${G}Connected: $clients devices${N}"
        echo -e "${Y}Speed limited: $limited devices${N}\n"
        
        echo -e "${W}1.${N} Speed Control ${C}[CUSTOM]${N}"
        echo -e "${W}2.${N} Block Device"
        echo -e "${W}3.${N} Monitor Bandwidth"
        echo -e "${W}4.${N} View Status"
        echo -e "${W}0.${N} Exit"
        
        read -p $'\n'"Choose: " opt
        
        case $opt in
            1) speed_control_menu ;;
            2) block_menu ;;
            3) monitor ;;
            4) view_all_speeds ;;
            0) echo -e "\n${C}By: senzore ganteng${N}\n"; exit ;;
        esac
    done
}

# ═══════════════════════════════════════════════════
# STARTUP
# ═══════════════════════════════════════════════════
main() {
    # Auto install on first run
    auto_install
    
    # Create names database if not exists
    touch "$DATA_DIR/names.db" 2>/dev/null
    
    header
    echo -e "${Y}Checking root...${N}"
    
    if ! su -c "id" &>/dev/null; then
        echo -e "${R}[✗] Root required!${N}"
        exit 1
    fi
    
    echo -e "${G}[✓] Root OK${N}"
    echo -e "${G}[✓] TTL at 65 (not changed)${N}"
    echo -e "${G}[✓] Ready!${N}\n"
    
    sleep 1
    
    main_menu
}

# RUN
main
