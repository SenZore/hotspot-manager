#!/data/data/com.termux/files/usr/bin/bash

# ═══════════════════════════════════════════════════
# TERMUX HOTSPOT MANAGER v6.0 - SIMPLIFIED
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
CLIENTS_DB="$CONFIG_DIR/clients.db"
BLOCKED_DB="$CONFIG_DIR/blocked.db"
PORTS_DB="$CONFIG_DIR/ports.db"

# Global vars
ROOT=0
INTERFACE="wlan0"
HOTSPOT_IP=""

# ═══════════════════════════════════════════════════
# BANNER
# ═══════════════════════════════════════════════════
banner() {
    clear
    echo -e "${CYAN}═══════════════════════════════════════════════════${NC}"
    echo -e "${WHITE}${BOLD}         HOTSPOT MANAGER v6.0${NC}"
    echo -e "${PURPLE}           By: senzore ganteng${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════${NC}\n"
}

# ═══════════════════════════════════════════════════
# ROOT CHECK
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
# INSTALL DEPS
# ═══════════════════════════════════════════════════
install_deps() {
    echo -e "${YELLOW}[*] Checking packages...${NC}"
    
    for pkg in iproute2 net-tools bc iptables ncurses-utils; do
        if ! dpkg -s "$pkg" &>/dev/null; then
            echo -e "${YELLOW}Installing $pkg...${NC}"
            pkg install -y "$pkg" &>/dev/null
        fi
    done
    
    echo -e "${GREEN}[✓] Ready${NC}"
}

# ═══════════════════════════════════════════════════
# DETECT INTERFACE
# ═══════════════════════════════════════════════════
detect_interface() {
    [ $ROOT -eq 0 ] && return
    
    # Find hotspot interface
    for iface in ap0 swlan0 wlan0 wlan1 rndis0; do
        local ip=$(su -c "ip addr show $iface 2>/dev/null | grep 'inet ' | grep -v '127.0.0.1' | awk '{print \$2}' | cut -d/ -f1")
        if [ -n "$ip" ]; then
            INTERFACE="$iface"
            HOTSPOT_IP="$ip"
            return
        fi
    done
}

# ═══════════════════════════════════════════════════
# INIT
# ═══════════════════════════════════════════════════
init_config() {
    mkdir -p "$CONFIG_DIR"
    touch "$CLIENTS_DB" "$BLOCKED_DB" "$PORTS_DB"
}

# ═══════════════════════════════════════════════════
# GET CLIENTS
# ═══════════════════════════════════════════════════
get_clients() {
    [ $ROOT -eq 0 ] && return
    
    detect_interface
    
    # Get all clients at once
    su -c "cat /proc/net/arp 2>/dev/null" | grep "$INTERFACE" | grep -v "00:00:00:00:00:00" | awk '{print $1}'
}

# ═══════════════════════════════════════════════════
# SHOW CLIENTS SIMPLE
# ═══════════════════════════════════════════════════
show_clients() {
    local clients=$(get_clients)
    
    if [ -z "$clients" ]; then
        echo -e "${RED}No devices connected${NC}"
        return 1
    fi
    
    echo -e "${YELLOW}Connected Devices:${NC}\n"
    
    local count=1
    while read ip; do
        [ -z "$ip" ] && continue
        
        local limit=$(grep "^$ip " "$CLIENTS_DB" 2>/dev/null | cut -d' ' -f2)
        [ -z "$limit" ] || [ "$limit" = "0" ] && limit="Unlimited" || limit="${limit} KB/s"
        
        printf "${CYAN}%2d.${NC} IP: ${WHITE}%-15s${NC}  Speed: ${YELLOW}%-12s${NC}\n" "$count" "$ip" "$limit"
        
        ((count++))
    done <<< "$clients"
    
    return 0
}

# ═══════════════════════════════════════════════════
# NETWORK STATS
# ═══════════════════════════════════════════════════
network_stats() {
    detect_interface
    local rx=$(cat /sys/class/net/$INTERFACE/statistics/rx_bytes 2>/dev/null || echo 0)
    local tx=$(cat /sys/class/net/$INTERFACE/statistics/tx_bytes 2>/dev/null || echo 0)
    
    echo "RX: $((rx/1048576)) MB | TX: $((tx/1048576)) MB"
}

# ═══════════════════════════════════════════════════
# REALTIME MONITOR
# ═══════════════════════════════════════════════════
monitor_stats() {
    banner
    echo -e "${CYAN}═══════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}${BOLD}        REAL-TIME MONITOR${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════${NC}\n"
    
    detect_interface
    echo -e "${GREEN}Interface: $INTERFACE${NC}"
    echo -e "${GREEN}Hotspot IP: $HOTSPOT_IP${NC}"
    echo -e "${YELLOW}Press Ctrl+C to exit${NC}\n"
    
    local stats="/sys/class/net/$INTERFACE/statistics"
    
    if [ ! -f "$stats/rx_bytes" ]; then
        echo -e "${RED}[✗] Interface not active${NC}"
        read -p "Press Enter..."
        return
    fi
    
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
        
        tput cup 8 0
        tput ed
        
        echo -e "${GREEN}Network Activity:${NC}"
        echo -e "Download: ${CYAN}$rx_rate KB/s${NC}"
        echo -e "Upload:   ${CYAN}$tx_rate KB/s${NC}"
        echo -e "Total RX: ${PURPLE}$((rx/1048576)) MB${NC}"
        echo -e "Total TX: ${PURPLE}$((tx/1048576)) MB${NC}"
        
        if [ $ROOT -eq 1 ]; then
            echo -e "\n${YELLOW}Connected Devices:${NC}"
            
            local clients=$(get_clients)
            if [ -n "$clients" ]; then
                local count=1
                while read ip; do
                    [ -z "$ip" ] && continue
                    
                    local limit=$(grep "^$ip " "$CLIENTS_DB" 2>/dev/null | cut -d' ' -f2)
                    [ -z "$limit" ] || [ "$limit" = "0" ] && limit="∞" || limit="${limit}KB/s"
                    
                    printf "%2d. %-15s  [%s]\n" "$count" "$ip" "$limit"
                    ((count++))
                done <<< "$clients"
            else
                echo "No devices"
            fi
        fi
        
        prev_rx=$rx
        prev_tx=$tx
    done
}

# ═══════════════════════════════════════════════════
# PORT FORWARDING - FIXED VERSION
# ═══════════════════════════════════════════════════
port_forward() {
    [ $ROOT -eq 0 ] && echo -e "${RED}Root required${NC}" && return
    
    banner
    echo -e "${CYAN}═══════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}${BOLD}        PORT FORWARDING${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════${NC}\n"
    
    detect_interface
    
    echo -e "${YELLOW}Hotspot Network: $HOTSPOT_IP${NC}\n"
    
    echo -e "${CYAN}1.${NC} Add Port Forward"
    echo -e "${CYAN}2.${NC} Remove Port Forward"
    echo -e "${CYAN}3.${NC} List Active Forwards"
    echo -e "${CYAN}4.${NC} Quick Minecraft (25565)"
    echo -e "${CYAN}5.${NC} Quick Web Server (8080)"
    echo -e "${CYAN}0.${NC} Back"
    
    read -p $'\n'"Choose: " opt
    
    case $opt in
        1)
            local clients=$(get_clients)
            
            # Option to forward to Termux itself
            echo -e "\n${YELLOW}Forward to:${NC}"
            echo -e "${CYAN}0.${NC} This device (Termux/localhost)"
            
            if [ -n "$clients" ]; then
                local -a list
                local i=1
                
                while read ip; do
                    [ -z "$ip" ] && continue
                    list[$i]="$ip"
                    printf "${CYAN}%d.${NC} %s\n" $i "$ip"
                    ((i++))
                done <<< "$clients"
                
                read -p $'\n'"Select [0-$((i-1))]: " sel
                
                local target_ip=""
                if [ "$sel" = "0" ]; then
                    target_ip="127.0.0.1"
                elif [ "$sel" -ge 1 ] && [ "$sel" -lt "$i" ]; then
                    target_ip="${list[$sel]}"
                else
                    return
                fi
            else
                echo -e "${YELLOW}No clients connected, forwarding to localhost${NC}"
                target_ip="127.0.0.1"
            fi
            
            read -p "Port number: " port
            read -p "Protocol (tcp/udp/both) [tcp]: " proto
            [ -z "$proto" ] && proto="tcp"
            
            echo -e "\n${YELLOW}Setting up port forward...${NC}"
            
            # Enable forwarding
            su -c "echo 1 > /proc/sys/net/ipv4/ip_forward"
            
            # Clear any existing rules for this port
            su -c "iptables -t nat -D PREROUTING -p tcp --dport $port -j DNAT --to-destination $target_ip:$port 2>/dev/null"
            su -c "iptables -t nat -D PREROUTING -p udp --dport $port -j DNAT --to-destination $target_ip:$port 2>/dev/null"
            
            if [ "$target_ip" = "127.0.0.1" ]; then
                # Forward to localhost (Termux)
                if [ "$proto" = "both" ] || [ "$proto" = "tcp" ]; then
                    su -c "iptables -t nat -A PREROUTING -p tcp --dport $port -j REDIRECT --to-port $port"
                fi
                if [ "$proto" = "both" ] || [ "$proto" = "udp" ]; then
                    su -c "iptables -t nat -A PREROUTING -p udp --dport $port -j REDIRECT --to-port $port"
                fi
            else
                # Forward to other device
                if [ "$proto" = "both" ] || [ "$proto" = "tcp" ]; then
                    su -c "iptables -t nat -A PREROUTING -p tcp --dport $port -j DNAT --to-destination $target_ip:$port"
                    su -c "iptables -A FORWARD -p tcp -d $target_ip --dport $port -j ACCEPT"
                fi
                if [ "$proto" = "both" ] || [ "$proto" = "udp" ]; then
                    su -c "iptables -t nat -A PREROUTING -p udp --dport $port -j DNAT --to-destination $target_ip:$port"
                    su -c "iptables -A FORWARD -p udp -d $target_ip --dport $port -j ACCEPT"
                fi
            fi
            
            # Ensure MASQUERADE
            su -c "iptables -t nat -C POSTROUTING -j MASQUERADE 2>/dev/null || iptables -t nat -A POSTROUTING -j MASQUERADE"
            
            # Accept forwarding
            su -c "iptables -P FORWARD ACCEPT 2>/dev/null"
            
            echo "$target_ip $port $proto" >> "$PORTS_DB"
            
            echo -e "\n${GREEN}Port forwarding active!${NC}"
            echo -e "${GREEN}Connect to: ${CYAN}$HOTSPOT_IP:$port${NC}"
            echo -e "${GREEN}Forwarding to: ${CYAN}$target_ip:$port ($proto)${NC}"
            ;;
            
        2)
            [ ! -s "$PORTS_DB" ] && echo -e "${RED}No active forwards${NC}" && read -p "Press Enter..." && return
            
            echo -e "\n${YELLOW}Active forwards:${NC}\n"
            local i=1
            local -a list
            
            while read line; do
                [ -z "$line" ] && continue
                list[$i]="$line"
                local ip=$(echo $line | cut -d' ' -f1)
                local port=$(echo $line | cut -d' ' -f2)
                local proto=$(echo $line | cut -d' ' -f3)
                
                printf "${CYAN}%d.${NC} Port %s (%s) -> %s\n" $i "$port" "$proto" "$ip"
                ((i++))
            done < "$PORTS_DB"
            
            read -p $'\n'"Remove [1-$((i-1))]: " sel
            
            if [ "$sel" -ge 1 ] && [ "$sel" -lt "$i" ]; then
                local rule="${list[$sel]}"
                local ip=$(echo $rule | cut -d' ' -f1)
                local port=$(echo $rule | cut -d' ' -f2)
                local proto=$(echo $rule | cut -d' ' -f3)
                
                echo -e "\n${YELLOW}Removing forward...${NC}"
                
                if [ "$ip" = "127.0.0.1" ]; then
                    su -c "iptables -t nat -D PREROUTING -p tcp --dport $port -j REDIRECT --to-port $port 2>/dev/null"
                    su -c "iptables -t nat -D PREROUTING -p udp --dport $port -j REDIRECT --to-port $port 2>/dev/null"
                else
                    su -c "iptables -t nat -D PREROUTING -p tcp --dport $port -j DNAT --to-destination $ip:$port 2>/dev/null"
                    su -c "iptables -t nat -D PREROUTING -p udp --dport $port -j DNAT --to-destination $ip:$port 2>/dev/null"
                    su -c "iptables -D FORWARD -p tcp -d $ip --dport $port -j ACCEPT 2>/dev/null"
                    su -c "iptables -D FORWARD -p udp -d $ip --dport $port -j ACCEPT 2>/dev/null"
                fi
                
                sed -i "/^$ip $port $proto$/d" "$PORTS_DB"
                echo -e "${GREEN}[✓] Removed${NC}"
            fi
            ;;
            
        3)
            echo -e "\n${YELLOW}Active Port Forwards:${NC}\n"
            
            if [ -s "$PORTS_DB" ]; then
                while read line; do
                    [ -z "$line" ] && continue
                    local ip=$(echo $line | cut -d' ' -f1)
                    local port=$(echo $line | cut -d' ' -f2)
                    local proto=$(echo $line | cut -d' ' -f3)
                    
                    echo -e "${CYAN}Port $port ($proto)${NC} -> ${WHITE}$ip${NC}"
                    echo -e "  Connect: ${GREEN}$HOTSPOT_IP:$port${NC}"
                done < "$PORTS_DB"
            else
                echo -e "${RED}No active forwards${NC}"
            fi
            ;;
            
        4)
            # Minecraft quick setup
            echo -e "\n${YELLOW}Minecraft Server Setup${NC}"
            
            local clients=$(get_clients)
            echo -e "\n${CYAN}0.${NC} Host on Termux"
            
            if [ -n "$clients" ]; then
                local -a list
                local i=1
                
                while read ip; do
                    [ -z "$ip" ] && continue
                    list[$i]="$ip"
                    printf "${CYAN}%d.${NC} %s\n" $i "$ip"
                    ((i++))
                done <<< "$clients"
                
                read -p $'\n'"Select host [0-$((i-1))]: " sel
                
                local mc_ip=""
                if [ "$sel" = "0" ]; then
                    mc_ip="127.0.0.1"
                elif [ "$sel" -ge 1 ] && [ "$sel" -lt "$i" ]; then
                    mc_ip="${list[$sel]}"
                else
                    return
                fi
            else
                mc_ip="127.0.0.1"
            fi
            
            echo -e "\n${YELLOW}Setting up Minecraft...${NC}"
            
            su -c "echo 1 > /proc/sys/net/ipv4/ip_forward"
            
            if [ "$mc_ip" = "127.0.0.1" ]; then
                su -c "iptables -t nat -A PREROUTING -p tcp --dport 25565 -j REDIRECT --to-port 25565"
                su -c "iptables -t nat -A PREROUTING -p udp --dport 25565 -j REDIRECT --to-port 25565"
            else
                su -c "iptables -t nat -A PREROUTING -p tcp --dport 25565 -j DNAT --to-destination $mc_ip:25565"
                su -c "iptables -t nat -A PREROUTING -p udp --dport 25565 -j DNAT --to-destination $mc_ip:25565"
                su -c "iptables -A FORWARD -p tcp -d $mc_ip --dport 25565 -j ACCEPT"
                su -c "iptables -A FORWARD -p udp -d $mc_ip --dport 25565 -j ACCEPT"
            fi
            
            su -c "iptables -t nat -C POSTROUTING -j MASQUERADE 2>/dev/null || iptables -t nat -A POSTROUTING -j MASQUERADE"
            su -c "iptables -P FORWARD ACCEPT 2>/dev/null"
            
            echo "$mc_ip 25565 both" >> "$PORTS_DB"
            
            echo -e "\n${GREEN}Minecraft server ready!${NC}"
            echo -e "${GREEN}Server IP: ${CYAN}$HOTSPOT_IP:25565${NC}"
            ;;
            
        5)
            # Web server quick setup
            echo -e "\n${YELLOW}Web Server Setup${NC}"
            
            local clients=$(get_clients)
            echo -e "\n${CYAN}0.${NC} Host on Termux"
            
            if [ -n "$clients" ]; then
                local -a list
                local i=1
                
                while read ip; do
                    [ -z "$ip" ] && continue
                    list[$i]="$ip"
                    printf "${CYAN}%d.${NC} %s\n" $i "$ip"
                    ((i++))
                done <<< "$clients"
                
                read -p $'\n'"Select host [0-$((i-1))]: " sel
                
                local web_ip=""
                if [ "$sel" = "0" ]; then
                    web_ip="127.0.0.1"
                elif [ "$sel" -ge 1 ] && [ "$sel" -lt "$i" ]; then
                    web_ip="${list[$sel]}"
                else
                    return
                fi
            else
                web_ip="127.0.0.1"
            fi
            
            echo -e "\n${YELLOW}Setting up web server...${NC}"
            
            su -c "echo 1 > /proc/sys/net/ipv4/ip_forward"
            
            if [ "$web_ip" = "127.0.0.1" ]; then
                su -c "iptables -t nat -A PREROUTING -p tcp --dport 8080 -j REDIRECT --to-port 8080"
            else
                su -c "iptables -t nat -A PREROUTING -p tcp --dport 8080 -j DNAT --to-destination $web_ip:8080"
                su -c "iptables -A FORWARD -p tcp -d $web_ip --dport 8080 -j ACCEPT"
            fi
            
            su -c "iptables -t nat -C POSTROUTING -j MASQUERADE 2>/dev/null || iptables -t nat -A POSTROUTING -j MASQUERADE"
            su -c "iptables -P FORWARD ACCEPT 2>/dev/null"
            
            echo "$web_ip 8080 tcp" >> "$PORTS_DB"
            
            echo -e "\n${GREEN}Web server ready!${NC}"
            echo -e "${GREEN}URL: ${CYAN}http://$HOTSPOT_IP:8080${NC}"
            ;;
    esac
    
    read -p $'\n'"Press Enter..."
}

# ═══════════════════════════════════════════════════
# SPEED CONTROL - SIMPLE TEXT
# ═══════════════════════════════════════════════════
set_speed() {
    [ $ROOT -eq 0 ] && echo -e "${RED}Root required${NC}" && return
    
    banner
    echo -e "${CYAN}═══════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}${BOLD}          SPEED CONTROL${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════${NC}\n"
    
    show_clients || { read -p "Press Enter..."; return; }
    
    local clients=$(get_clients)
    local -a list
    local i=1
    
    while read ip; do
        [ -z "$ip" ] && continue
        list[$i]="$ip"
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
            apply_limit "${list[$j]}"
        done
    elif [ "$sel" -ge 1 ] && [ "$sel" -lt "$i" ]; then
        apply_limit "${list[$sel]}"
    fi
    
    read -p "Press Enter..."
}

# ═══════════════════════════════════════════════════
# BLOCK/UNBLOCK/KICK
# ═══════════════════════════════════════════════════
block_client() {
    [ $ROOT -eq 0 ] && echo -e "${RED}Root required${NC}" && return
    
    banner
    echo -e "${CYAN}═══════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}${BOLD}          BLOCK DEVICE${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════${NC}\n"
    
    show_clients || { read -p "Press Enter..."; return; }
    
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
        su -c "iptables -I FORWARD -s $ip -j DROP"
        su -c "iptables -I FORWARD -d $ip -j DROP"
        echo "$ip" >> "$BLOCKED_DB"
        echo -e "${GREEN}[✓] Blocked${NC}"
    fi
    
    read -p "Press Enter..."
}

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
    
    while read ip; do
        [ -z "$ip" ] && continue
        list[$i]="$ip"
        printf "${CYAN}%d.${NC} %s\n" $i "$ip"
        ((i++))
    done < "$BLOCKED_DB"
    
    read -p $'\n'"Select [1-$((i-1))]: " sel
    
    if [ "$sel" -ge 1 ] && [ "$sel" -lt "$i" ]; then
        local ip="${list[$sel]}"
        
        echo -e "\n${YELLOW}Unblocking $ip...${NC}"
        su -c "iptables -D FORWARD -s $ip -j DROP 2>/dev/null"
        su -c "iptables -D FORWARD -d $ip -j DROP 2>/dev/null"
        sed -i "/^$ip$/d" "$BLOCKED_DB"
        echo -e "${GREEN}[✓] Unblocked${NC}"
    fi
    
    read -p "Press Enter..."
}

kick_client() {
    [ $ROOT -eq 0 ] && echo -e "${RED}Root required${NC}" && return
    
    banner
    echo -e "${CYAN}═══════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}${BOLD}          KICK DEVICE${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════${NC}\n"
    
    show_clients || { read -p "Press Enter..."; return; }
    
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
        
        [ $ROOT -eq 1 ] && show_clients
        
        echo -e "\n${CYAN}═══════════════════════════════════════════════════${NC}"
        echo -e "${CYAN}1.${NC} Speed Control"
        echo -e "${CYAN}2.${NC} Port Forwarding"
        echo -e "${CYAN}3.${NC} Block Device"
        echo -e "${CYAN}4.${NC} Unblock Device" 
        echo -e "${CYAN}5.${NC} Kick Device"
        echo -e "${CYAN}0.${NC} Back"
        echo -e "${CYAN}═══════════════════════════════════════════════════${NC}"
        
        read -p $'\n'"Choose: " opt
        
        case $opt in
            1) set_speed ;;
            2) port_forward ;;
            3) block_client ;;
            4) unblock_client ;;
            5) kick_client ;;
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
    
    echo -e "${WHITE}${BOLD}Hotspot Manager v6.0${NC}"
    echo -e "${YELLOW}Simplified & Fixed Edition${NC}\n"
    
    echo -e "${CYAN}Features:${NC}"
    echo -e "${GREEN}✓${NC} Simple text interface"
    echo -e "${GREEN}✓${NC} Working port forwarding"
    echo -e "${GREEN}✓${NC} Speed control"
    echo -e "${GREEN}✓${NC} Device management"
    
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
        
        echo -e "${YELLOW}Root:${NC}       $([ $ROOT -eq 1 ] && echo -e "${GREEN}YES${NC}" || echo -e "${RED}NO${NC}")"
        echo -e "${YELLOW}Interface:${NC}  ${GREEN}$INTERFACE${NC}"
        echo -e "${YELLOW}Hotspot IP:${NC} ${GREEN}${HOTSPOT_IP:-Not detected}${NC}"
        echo -e "${YELLOW}Network:${NC}    $(network_stats)"
        
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
