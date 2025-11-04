#!/data/data/com.termux/files/usr/bin/bash

# ═══════════════════════════════════════════════════
# HOTSPOT MANAGER v11.0 - FAST & FIXED
# By: senzore ganteng
# ═══════════════════════════════════════════════════

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m'
BOLD='\033[1m'

# Config
CONFIG_DIR="$HOME/.hotspot_manager"
SPEED_DB="$CONFIG_DIR/speed.db"
BLOCK_DB="$CONFIG_DIR/blocked.db"

# Vars
ROOT=0
IFACE=""
IP=""

# ═══════════════════════════════════════════════════
# BANNER
# ═══════════════════════════════════════════════════
banner() {
    clear
    echo -e "${CYAN}═══════════════════════════════════════════════════${NC}"
    echo -e "${WHITE}${BOLD}      HOTSPOT MANAGER v11.0 FAST${NC}"
    echo -e "${CYAN}           By: senzore ganteng${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════${NC}\n"
}

# ═══════════════════════════════════════════════════
# QUICK ROOT CHECK
# ═══════════════════════════════════════════════════
check_root() {
    if su -c "id" 2>/dev/null | grep -q "uid=0"; then
        ROOT=1
        echo -e "${GREEN}[✓] Root OK${NC}"
        
        # Enable IP forward
        su -c "echo 1 > /proc/sys/net/ipv4/ip_forward" 2>/dev/null
        su -c "sysctl -w net.ipv4.ip_forward=1" &>/dev/null
    else
        echo -e "${RED}[✗] No Root${NC}"
        echo -e "${YELLOW}Speed control needs root!${NC}"
        sleep 2
    fi
}

# ═══════════════════════════════════════════════════
# FIND INTERFACE
# ═══════════════════════════════════════════════════
find_interface() {
    [ $ROOT -eq 0 ] && IFACE="wlan0" && return
    
    # Find active hotspot interface
    for i in ap0 swlan0 wlan0 wlan1 rmnet_data1 rndis0; do
        local test_ip=$(su -c "ip addr show $i 2>/dev/null | grep 'inet ' | grep -v '127.0.0.1' | awk '{print \$2}' | cut -d/ -f1")
        if [ -n "$test_ip" ]; then
            IFACE="$i"
            IP="$test_ip"
            return
        fi
    done
    IFACE="wlan0"
}

# ═══════════════════════════════════════════════════
# GET CLIENTS
# ═══════════════════════════════════════════════════
get_clients() {
    [ $ROOT -eq 0 ] && return
    find_interface
    su -c "cat /proc/net/arp 2>/dev/null | grep '$IFACE' | grep -v '00:00:00:00:00:00' | awk '{print \$1}'"
}

# ═══════════════════════════════════════════════════
# SHOW CLIENTS
# ═══════════════════════════════════════════════════
show_clients() {
    echo -e "${YELLOW}Connected Devices:${NC}\n"
    
    local clients=$(get_clients)
    [ -z "$clients" ] && echo -e "${RED}No devices${NC}" && return 1
    
    local n=1
    while read ip; do
        [ -z "$ip" ] && continue
        local speed=$(grep "^$ip " "$SPEED_DB" 2>/dev/null | cut -d' ' -f2)
        [ -z "$speed" ] || [ "$speed" = "0" ] && speed="Unlimited" || speed="${speed}KB/s"
        printf "${CYAN}%2d.${NC} %-15s [${YELLOW}%s${NC}]\n" "$n" "$ip" "$speed"
        ((n++))
    done <<< "$clients"
    
    return 0
}

# ═══════════════════════════════════════════════════
# SPEED LIMITER - FIXED FOR ALL DEVICES
# ═══════════════════════════════════════════════════
apply_speed() {
    local ip=$1
    local speed=$2
    
    echo -e "${YELLOW}Setting $ip to ${speed}KB/s...${NC}"
    
    # Remove old rules
    su -c "tc filter del dev $IFACE protocol ip parent 1: prio 1 handle 800::$ip u32 match ip dst $ip 2>/dev/null"
    su -c "tc filter del dev $IFACE protocol ip parent ffff: prio 1 handle 800::$ip u32 match ip src $ip 2>/dev/null"
    su -c "tc class del dev $IFACE parent 1:1 classid 1:$(echo $ip | cut -d. -f4) 2>/dev/null"
    
    if [ "$speed" = "0" ]; then
        # Remove limit
        sed -i "/^$ip /d" "$SPEED_DB" 2>/dev/null
        echo -e "${GREEN}[✓] Limit removed${NC}"
        return
    fi
    
    # FIXED: Setup that works for ALL devices (mobile + PC)
    
    # 1. Setup root qdisc if not exists
    su -c "tc qdisc show dev $IFACE | grep -q 'htb 1:'" || {
        su -c "tc qdisc add dev $IFACE root handle 1: htb default 999"
        su -c "tc class add dev $IFACE parent 1: classid 1:1 htb rate 1000mbit"
        su -c "tc class add dev $IFACE parent 1:1 classid 1:999 htb rate 1000mbit"
    }
    
    # 2. Setup ingress for upload control
    su -c "tc qdisc show dev $IFACE | grep -q 'ingress'" || {
        su -c "tc qdisc add dev $IFACE handle ffff: ingress"
    }
    
    # 3. Create class for this IP
    local classid="1:$(echo $ip | cut -d. -f4)"
    local rate=$((speed * 8))  # Convert KB/s to kbit
    
    su -c "tc class add dev $IFACE parent 1:1 classid $classid htb rate ${rate}kbit ceil ${rate}kbit"
    
    # 4. Add SFQ for fairness
    su -c "tc qdisc add dev $IFACE parent $classid handle $(echo $ip | cut -d. -f4): sfq perturb 10"
    
    # 5. IMPORTANT: Filter both directions for ALL traffic types
    
    # Download TO device (dst)
    su -c "tc filter add dev $IFACE protocol ip parent 1: prio 1 u32 match ip dst $ip flowid $classid"
    
    # Upload FROM device (src) - using policing for ingress
    su -c "tc filter add dev $IFACE parent ffff: protocol ip prio 1 u32 match ip src $ip police rate ${rate}kbit burst 10k drop flowid :1"
    
    # 6. Also use iptables marking for better control
    su -c "iptables -t mangle -D FORWARD -d $ip -j MARK --set-mark $(echo $ip | cut -d. -f4) 2>/dev/null"
    su -c "iptables -t mangle -A FORWARD -d $ip -j MARK --set-mark $(echo $ip | cut -d. -f4)"
    su -c "tc filter add dev $IFACE parent 1: protocol ip prio 2 handle $(echo $ip | cut -d. -f4) fw flowid $classid"
    
    # 7. For WiFi clients specifically (helps with mobile)
    su -c "iptables -t mangle -D PREROUTING -s $ip -j MARK --set-mark $(echo $ip | cut -d. -f4) 2>/dev/null"
    su -c "iptables -t mangle -A PREROUTING -s $ip -j MARK --set-mark $(echo $ip | cut -d. -f4)"
    
    # Save to database
    sed -i "/^$ip /d" "$SPEED_DB" 2>/dev/null
    echo "$ip $speed" >> "$SPEED_DB"
    
    echo -e "${GREEN}[✓] Speed limit applied${NC}"
}

# ═══════════════════════════════════════════════════
# SPEED CONTROL MENU
# ═══════════════════════════════════════════════════
speed_control() {
    [ $ROOT -eq 0 ] && echo -e "${RED}Root required${NC}" && sleep 1 && return
    
    banner
    echo -e "${CYAN}══════ SPEED CONTROL ══════${NC}\n"
    
    show_clients || { sleep 1; return; }
    
    local clients=$(get_clients)
    local -a list
    local i=1
    
    while read ip; do
        [ -z "$ip" ] && continue
        list[$i]="$ip"
        ((i++))
    done <<< "$clients"
    
    echo -e "\n${CYAN}0.${NC} ALL devices"
    echo -e "${CYAN}99.${NC} Remove ALL limits"
    
    read -p $'\n'"Select [0-$((i-1))]: " sel
    
    if [ "$sel" = "99" ]; then
        echo -e "\n${YELLOW}Removing all limits...${NC}"
        find_interface
        
        # Clear everything
        su -c "tc qdisc del dev $IFACE root 2>/dev/null"
        su -c "tc qdisc del dev $IFACE ingress 2>/dev/null"
        su -c "iptables -t mangle -F 2>/dev/null"
        > "$SPEED_DB"
        
        echo -e "${GREEN}[✓] All limits removed${NC}"
        sleep 1
        return
    fi
    
    read -p "Speed limit KB/s (0=unlimited): " speed
    
    [[ ! "$speed" =~ ^[0-9]+$ ]] && echo -e "${RED}Invalid${NC}" && sleep 1 && return
    
    find_interface
    
    if [ "$sel" = "0" ]; then
        # Apply to all
        echo ""
        for j in "${!list[@]}"; do
            [ -z "${list[$j]}" ] && continue
            apply_speed "${list[$j]}" "$speed"
        done
    elif [ "$sel" -ge 1 ] && [ "$sel" -lt "$i" ]; then
        echo ""
        apply_speed "${list[$sel]}" "$speed"
    else
        echo -e "${RED}Invalid selection${NC}"
    fi
    
    sleep 2
}

# ═══════════════════════════════════════════════════
# BLOCK/UNBLOCK
# ═══════════════════════════════════════════════════
block_device() {
    [ $ROOT -eq 0 ] && echo -e "${RED}Root required${NC}" && sleep 1 && return
    
    banner
    echo -e "${CYAN}══════ BLOCK DEVICE ══════${NC}\n"
    
    show_clients || { sleep 1; return; }
    
    local clients=$(get_clients)
    local -a list
    local i=1
    
    while read ip; do
        [ -z "$ip" ] && continue
        list[$i]="$ip"
        ((i++))
    done <<< "$clients"
    
    read -p $'\n'"Select [1-$((i-1))]: " sel
    
    if [ "$sel" -ge 1 ] && [ "$sel" -lt "$i" ]; then
        local ip="${list[$sel]}"
        echo -e "\n${YELLOW}Blocking $ip...${NC}"
        
        # Block with iptables
        su -c "iptables -I INPUT -s $ip -j DROP"
        su -c "iptables -I FORWARD -s $ip -j DROP"
        su -c "iptables -I FORWARD -d $ip -j DROP"
        
        echo "$ip" >> "$BLOCK_DB"
        echo -e "${GREEN}[✓] Blocked${NC}"
    fi
    
    sleep 1
}

unblock_device() {
    [ $ROOT -eq 0 ] && echo -e "${RED}Root required${NC}" && sleep 1 && return
    
    banner
    echo -e "${CYAN}══════ UNBLOCK DEVICE ══════${NC}\n"
    
    [ ! -s "$BLOCK_DB" ] && echo -e "${RED}No blocked devices${NC}" && sleep 1 && return
    
    echo -e "${YELLOW}Blocked:${NC}\n"
    
    local i=1
    local -a list
    
    while read ip; do
        [ -z "$ip" ] && continue
        list[$i]="$ip"
        printf "${CYAN}%d.${NC} %s\n" $i "$ip"
        ((i++))
    done < "$BLOCK_DB"
    
    read -p $'\n'"Select [1-$((i-1))]: " sel
    
    if [ "$sel" -ge 1 ] && [ "$sel" -lt "$i" ]; then
        local ip="${list[$sel]}"
        echo -e "\n${YELLOW}Unblocking $ip...${NC}"
        
        su -c "iptables -D INPUT -s $ip -j DROP 2>/dev/null"
        su -c "iptables -D FORWARD -s $ip -j DROP 2>/dev/null"
        su -c "iptables -D FORWARD -d $ip -j DROP 2>/dev/null"
        
        sed -i "/^$ip$/d" "$BLOCK_DB"
        echo -e "${GREEN}[✓] Unblocked${NC}"
    fi
    
    sleep 1
}

# ═══════════════════════════════════════════════════
# KICK DEVICE
# ═══════════════════════════════════════════════════
kick_device() {
    [ $ROOT -eq 0 ] && echo -e "${RED}Root required${NC}" && sleep 1 && return
    
    banner
    echo -e "${CYAN}══════ KICK DEVICE ══════${NC}\n"
    
    show_clients || { sleep 1; return; }
    
    local clients=$(get_clients)
    local -a list
    local i=1
    
    while read ip; do
        [ -z "$ip" ] && continue
        list[$i]="$ip"
        ((i++))
    done <<< "$clients"
    
    read -p $'\n'"Select [1-$((i-1))]: " sel
    
    if [ "$sel" -ge 1 ] && [ "$sel" -lt "$i" ]; then
        find_interface
        local ip="${list[$sel]}"
        
        echo -e "\n${YELLOW}Kicking $ip...${NC}"
        su -c "ip neigh del $ip dev $IFACE 2>/dev/null"
        su -c "arp -d $ip 2>/dev/null"
        echo -e "${GREEN}[✓] Kicked${NC}"
    fi
    
    sleep 1
}

# ═══════════════════════════════════════════════════
# MONITOR
# ═══════════════════════════════════════════════════
monitor() {
    banner
    echo -e "${CYAN}══════ MONITOR ══════${NC}\n"
    
    find_interface
    echo -e "${GREEN}Interface: $IFACE${NC}"
    echo -e "${GREEN}IP: $IP${NC}"
    echo -e "${YELLOW}Ctrl+C to exit${NC}\n"
    
    local stats="/sys/class/net/$IFACE/statistics"
    
    [ ! -f "$stats/rx_bytes" ] && echo -e "${RED}Interface not active${NC}" && sleep 2 && return
    
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
        
        tput cup 7 0
        tput ed
        
        echo -e "${CYAN}Speed:${NC}"
        echo -e "↓ ${rx_rate} KB/s"
        echo -e "↑ ${tx_rate} KB/s"
        echo -e "\n${CYAN}Total:${NC}"
        echo -e "RX: $((rx/1048576)) MB"
        echo -e "TX: $((tx/1048576)) MB"
        
        if [ $ROOT -eq 1 ]; then
            echo -e "\n${CYAN}Devices:${NC}"
            local clients=$(get_clients)
            if [ -n "$clients" ]; then
                while read ip; do
                    [ -z "$ip" ] && continue
                    local speed=$(grep "^$ip " "$SPEED_DB" 2>/dev/null | cut -d' ' -f2)
                    [ -z "$speed" ] || [ "$speed" = "0" ] && speed="∞" || speed="${speed}KB/s"
                    echo "$ip [$speed]"
                done <<< "$clients"
            else
                echo "None"
            fi
        fi
        
        prev_rx=$rx
        prev_tx=$tx
    done
}

# ═══════════════════════════════════════════════════
# MINECRAFT SERVER
# ═══════════════════════════════════════════════════
minecraft() {
    banner
    echo -e "${CYAN}══════ MINECRAFT SERVER ══════${NC}\n"
    
    find_interface
    
    echo -e "${GREEN}For friends in same room/WiFi:${NC}"
    echo -e "Share this IP: ${CYAN}${IP}:25565${NC}\n"
    
    echo -e "${YELLOW}For online friends (bypass CGNAT):${NC}\n"
    
    echo -e "${CYAN}1.${NC} Playit.gg (Best for Asia)"
    echo -e "${CYAN}2.${NC} ngrok (Global)"
    echo -e "${CYAN}0.${NC} Back"
    
    read -p $'\n'"Choose: " opt
    
    case $opt in
        1)
            if [ ! -f "$HOME/playit" ]; then
                echo -e "\n${YELLOW}Installing playit.gg...${NC}"
                case $(uname -m) in
                    aarch64|arm64) wget -O $HOME/playit "https://playit.gg/downloads/playit-linux-aarch64" -q --show-progress ;;
                    arm*) wget -O $HOME/playit "https://playit.gg/downloads/playit-linux-arm7" -q --show-progress ;;
                esac
                chmod +x $HOME/playit
            fi
            
            echo -e "\n${YELLOW}Starting...${NC}"
            pkill -f playit 2>/dev/null
            $HOME/playit &
            
            echo -e "\n${GREEN}Playit.gg started!${NC}"
            echo -e "1. Check the link above"
            echo -e "2. Login (FREE)"
            echo -e "3. Choose Singapore region"
            echo -e "4. Share address with friends!"
            ;;
            
        2)
            if [ ! -f "$HOME/ngrok" ]; then
                echo -e "\n${YELLOW}Installing ngrok...${NC}"
                case $(uname -m) in
                    aarch64|arm64) wget -O ng.tgz "https://bin.equinox.io/c/bNyj1mQVY4c/ngrok-v3-stable-linux-arm64.tgz" -q --show-progress ;;
                    arm*) wget -O ng.tgz "https://bin.equinox.io/c/bNyj1mQVY4c/ngrok-v3-stable-linux-arm.tgz" -q --show-progress ;;
                esac
                tar -xzf ng.tgz -C $HOME && rm ng.tgz
                chmod +x $HOME/ngrok
            fi
            
            if ! grep -q "authtoken:" $HOME/.ngrok2/ngrok.yml 2>/dev/null; then
                echo -e "\nGet token from: ${CYAN}https://ngrok.com${NC}"
                read -p "Token: " token
                [ -n "$token" ] && $HOME/ngrok config add-authtoken "$token"
            fi
            
            echo -e "\n${YELLOW}Starting...${NC}"
            pkill -f ngrok 2>/dev/null
            $HOME/ngrok tcp 25565 --region ap &
            
            sleep 3
            echo -e "\n${GREEN}Check terminal for address!${NC}"
            ;;
    esac
    
    read -p $'\n'"Press Enter..."
}

# ═══════════════════════════════════════════════════
# MAIN MENU
# ═══════════════════════════════════════════════════
main() {
    # Init
    mkdir -p "$CONFIG_DIR"
    touch "$SPEED_DB" "$BLOCK_DB"
    
    while true; do
        banner
        find_interface
        
        echo -e "${CYAN}Interface:${NC} $IFACE"
        echo -e "${CYAN}IP:${NC} ${IP:-Not detected}"
        echo -e "${CYAN}Root:${NC} $([ $ROOT -eq 1 ] && echo -e "${GREEN}YES${NC}" || echo -e "${RED}NO${NC}")"
        
        echo -e "\n${CYAN}═══════════════════════════════════════════════════${NC}"
        echo -e "${CYAN}1.${NC} Speed Control ${GREEN}[FIXED]${NC}"
        echo -e "${CYAN}2.${NC} Block Device"
        echo -e "${CYAN}3.${NC} Unblock Device"
        echo -e "${CYAN}4.${NC} Kick Device"
        echo -e "${CYAN}5.${NC} Monitor"
        echo -e "${CYAN}6.${NC} Minecraft Server"
        echo -e "${CYAN}0.${NC} Exit"
        echo -e "${CYAN}═══════════════════════════════════════════════════${NC}"
        
        read -p $'\n'"Choose: " opt
        
        case $opt in
            1) speed_control ;;
            2) block_device ;;
            3) unblock_device ;;
            4) kick_device ;;
            5) monitor ;;
            6) minecraft ;;
            0) echo -e "\n${CYAN}By: senzore ganteng${NC}\n"; exit ;;
        esac
    done
}

# START
banner
echo -e "${CYAN}Starting...${NC}\n"
check_root
sleep 1
main
