#!/data/data/com.termux/files/usr/bin/bash

# ═══════════════════════════════════════════════════
# TERMUX HOTSPOT MANAGER v7.0 - PUBLIC ACCESS
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
LOCAL_IP=""
PUBLIC_IP=""
PUBLIC_REACHABLE=0

# ═══════════════════════════════════════════════════
# BANNER
# ═══════════════════════════════════════════════════
banner() {
    clear
    echo -e "${CYAN}═══════════════════════════════════════════════════${NC}"
    echo -e "${WHITE}${BOLD}       HOTSPOT MANAGER v7.0 - PUBLIC${NC}"
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
    
    for pkg in iproute2 net-tools bc iptables ncurses-utils curl nmap-ncat; do
        if ! dpkg -s "$pkg" &>/dev/null; then
            echo -e "${YELLOW}Installing $pkg...${NC}"
            pkg install -y "$pkg" &>/dev/null
        fi
    done
    
    echo -e "${GREEN}[✓] Ready${NC}"
}

# ═══════════════════════════════════════════════════
# GET PUBLIC IP AND TEST
# ═══════════════════════════════════════════════════
get_public_ip() {
    echo -e "${YELLOW}[*] Getting public IP...${NC}"
    
    # Try multiple services
    PUBLIC_IP=$(curl -s --connect-timeout 3 ifconfig.me || \
                curl -s --connect-timeout 3 icanhazip.com || \
                curl -s --connect-timeout 3 ipinfo.io/ip || \
                curl -s --connect-timeout 3 api.ipify.org || \
                echo "")
    
    if [ -n "$PUBLIC_IP" ]; then
        echo -e "${GREEN}[✓] Public IP: $PUBLIC_IP${NC}"
        
        # Test if public IP is reachable
        echo -e "${YELLOW}[*] Testing public IP reachability...${NC}"
        
        # Try to ping ourselves (some IPs don't respond to ping)
        if timeout 2 ping -c 1 "$PUBLIC_IP" &>/dev/null; then
            PUBLIC_REACHABLE=1
            echo -e "${GREEN}[✓] Public IP is REACHABLE (pingable)${NC}"
        else
            # Try TCP connection test on common port
            if timeout 2 nc -zv "$PUBLIC_IP" 80 &>/dev/null || timeout 2 nc -zv "$PUBLIC_IP" 443 &>/dev/null; then
                PUBLIC_REACHABLE=1
                echo -e "${GREEN}[✓] Public IP is REACHABLE (TCP)${NC}"
            else
                PUBLIC_REACHABLE=0
                echo -e "${YELLOW}[!] Public IP not pingable (might be behind CGNAT)${NC}"
                echo -e "${YELLOW}[!] Port forwarding may only work on local network${NC}"
            fi
        fi
    else
        echo -e "${RED}[✗] Could not get public IP${NC}"
        PUBLIC_IP="Unknown"
    fi
}

# ═══════════════════════════════════════════════════
# DETECT INTERFACE
# ═══════════════════════════════════════════════════
detect_interface() {
    [ $ROOT -eq 0 ] && return
    
    # Find hotspot interface
    for iface in ap0 swlan0 wlan0 wlan1 rmnet_data0 rmnet_data1 rndis0; do
        local ip=$(su -c "ip addr show $iface 2>/dev/null | grep 'inet ' | grep -v '127.0.0.1' | awk '{print \$2}' | cut -d/ -f1")
        if [ -n "$ip" ]; then
            INTERFACE="$iface"
            LOCAL_IP="$ip"
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
# PORT FORWARDING - PUBLIC ACCESS FIXED
# ═══════════════════════════════════════════════════
port_forward() {
    [ $ROOT -eq 0 ] && echo -e "${RED}Root required${NC}" && return
    
    banner
    echo -e "${CYAN}═══════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}${BOLD}      PUBLIC PORT FORWARDING${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════${NC}\n"
    
    detect_interface
    get_public_ip
    
    echo -e "\n${YELLOW}Network Information:${NC}"
    echo -e "Local IP: ${GREEN}$LOCAL_IP${NC}"
    echo -e "Public IP: ${GREEN}$PUBLIC_IP${NC}"
    
    if [ $PUBLIC_REACHABLE -eq 0 ]; then
        echo -e "\n${YELLOW}⚠ WARNING: Public IP not reachable from outside${NC}"
        echo -e "${YELLOW}Port forwarding will work on LOCAL NETWORK ONLY${NC}"
        echo -e "${YELLOW}Share this IP with local devices: ${GREEN}$LOCAL_IP${NC}"
    else
        echo -e "\n${GREEN}✓ Public IP is reachable!${NC}"
        echo -e "${GREEN}Share this IP with anyone: $PUBLIC_IP${NC}"
    fi
    
    echo -e "\n${CYAN}1.${NC} Quick Minecraft Server (25565)"
    echo -e "${CYAN}2.${NC} Custom Port Forward"
    echo -e "${CYAN}3.${NC} List Active Forwards"
    echo -e "${CYAN}4.${NC} Remove Port Forward"
    echo -e "${CYAN}5.${NC} Test Port"
    echo -e "${CYAN}0.${NC} Back"
    
    read -p $'\n'"Choose: " opt
    
    case $opt in
        1)
            # Minecraft quick setup
            echo -e "\n${YELLOW}Setting up Minecraft Server Port...${NC}"
            
            # Find who has the server
            local clients=$(get_clients)
            echo -e "\n${YELLOW}Where is the Minecraft server running?${NC}"
            echo -e "${CYAN}0.${NC} This device (Termux/localhost)"
            
            if [ -n "$clients" ]; then
                local -a list
                local i=1
                
                while read ip; do
                    [ -z "$ip" ] && continue
                    list[$i]="$ip"
                    
                    # Test if port 25565 is open on this device
                    local status=""
                    if timeout 1 nc -zv "$ip" 25565 &>/dev/null; then
                        status="${GREEN}[DETECTED]${NC}"
                    fi
                    
                    printf "${CYAN}%d.${NC} %s %s\n" $i "$ip" "$status"
                    ((i++))
                done <<< "$clients"
                
                read -p $'\n'"Select [0-$((i-1))]: " sel
                
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
            
            echo -e "\n${YELLOW}Configuring port forwarding...${NC}"
            
            # Enable IP forwarding
            su -c "echo 1 > /proc/sys/net/ipv4/ip_forward"
            su -c "sysctl -w net.ipv4.ip_forward=1" &>/dev/null
            
            # Clear existing rules
            su -c "iptables -t nat -D PREROUTING -p tcp --dport 25565 -j DNAT --to-destination $mc_ip:25565 2>/dev/null"
            su -c "iptables -t nat -D PREROUTING -p udp --dport 25565 -j DNAT --to-destination $mc_ip:25565 2>/dev/null"
            
            # Add new rules
            if [ "$mc_ip" = "127.0.0.1" ]; then
                # For localhost
                su -c "iptables -t nat -A PREROUTING -i $INTERFACE -p tcp --dport 25565 -j REDIRECT --to-port 25565"
                su -c "iptables -t nat -A PREROUTING -i $INTERFACE -p udp --dport 25565 -j REDIRECT --to-port 25565"
            else
                # For other device
                su -c "iptables -t nat -A PREROUTING -i $INTERFACE -p tcp --dport 25565 -j DNAT --to-destination $mc_ip:25565"
                su -c "iptables -t nat -A PREROUTING -i $INTERFACE -p udp --dport 25565 -j DNAT --to-destination $mc_ip:25565"
                su -c "iptables -A FORWARD -p tcp -d $mc_ip --dport 25565 -m state --state NEW,ESTABLISHED,RELATED -j ACCEPT"
                su -c "iptables -A FORWARD -p udp -d $mc_ip --dport 25565 -m state --state NEW,ESTABLISHED,RELATED -j ACCEPT"
            fi
            
            # Enable masquerading
            su -c "iptables -t nat -C POSTROUTING -o $INTERFACE -j MASQUERADE 2>/dev/null || iptables -t nat -A POSTROUTING -o $INTERFACE -j MASQUERADE"
            
            # Accept forwarding
            su -c "iptables -P FORWARD ACCEPT"
            
            # For mobile data, also add rules for rmnet interfaces
            for rmnet in rmnet_data0 rmnet_data1 rmnet_data2; do
                if ip link show $rmnet &>/dev/null; then
                    su -c "iptables -t nat -C POSTROUTING -o $rmnet -j MASQUERADE 2>/dev/null || iptables -t nat -A POSTROUTING -o $rmnet -j MASQUERADE"
                fi
            done
            
            echo "$mc_ip 25565 both" >> "$PORTS_DB"
            
            echo -e "\n${GREEN}════════════════════════════════════════════════${NC}"
            echo -e "${GREEN}     MINECRAFT SERVER CONFIGURED!${NC}"
            echo -e "${GREEN}════════════════════════════════════════════════${NC}"
            
            if [ $PUBLIC_REACHABLE -eq 1 ]; then
                echo -e "\n${WHITE}Share with friends:${NC}"
                echo -e "${CYAN}${BOLD}$PUBLIC_IP:25565${NC}"
                echo -e "\n${YELLOW}Testing if port is open...${NC}"
                
                # Test the port
                if timeout 2 nc -zv "$LOCAL_IP" 25565 &>/dev/null; then
                    echo -e "${GREEN}[✓] Port 25565 is OPEN locally${NC}"
                else
                    echo -e "${YELLOW}[!] Port 25565 not responding (is server running?)${NC}"
                fi
            else
                echo -e "\n${WHITE}For LOCAL network friends:${NC}"
                echo -e "${CYAN}${BOLD}$LOCAL_IP:25565${NC}"
                echo -e "\n${YELLOW}Note: Only devices on same WiFi can connect${NC}"
            fi
            
            echo -e "\n${YELLOW}Server hosted on: $mc_ip${NC}"
            ;;
            
        2)
            # Custom port
            echo -e "\n${YELLOW}Custom Port Forward${NC}"
            
            read -p "Port number: " port
            read -p "Protocol (tcp/udp/both) [tcp]: " proto
            [ -z "$proto" ] && proto="tcp"
            
            local clients=$(get_clients)
            echo -e "\n${YELLOW}Forward to:${NC}"
            echo -e "${CYAN}0.${NC} This device (localhost)"
            
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
                target_ip="127.0.0.1"
            fi
            
            echo -e "\n${YELLOW}Setting up port forward...${NC}"
            
            su -c "echo 1 > /proc/sys/net/ipv4/ip_forward"
            su -c "sysctl -w net.ipv4.ip_forward=1" &>/dev/null
            
            if [ "$target_ip" = "127.0.0.1" ]; then
                if [ "$proto" = "both" ] || [ "$proto" = "tcp" ]; then
                    su -c "iptables -t nat -A PREROUTING -i $INTERFACE -p tcp --dport $port -j REDIRECT --to-port $port"
                fi
                if [ "$proto" = "both" ] || [ "$proto" = "udp" ]; then
                    su -c "iptables -t nat -A PREROUTING -i $INTERFACE -p udp --dport $port -j REDIRECT --to-port $port"
                fi
            else
                if [ "$proto" = "both" ] || [ "$proto" = "tcp" ]; then
                    su -c "iptables -t nat -A PREROUTING -i $INTERFACE -p tcp --dport $port -j DNAT --to-destination $target_ip:$port"
                    su -c "iptables -A FORWARD -p tcp -d $target_ip --dport $port -j ACCEPT"
                fi
                if [ "$proto" = "both" ] || [ "$proto" = "udp" ]; then
                    su -c "iptables -t nat -A PREROUTING -i $INTERFACE -p udp --dport $port -j DNAT --to-destination $target_ip:$port"
                    su -c "iptables -A FORWARD -p udp -d $target_ip --dport $port -j ACCEPT"
                fi
            fi
            
            su -c "iptables -t nat -C POSTROUTING -o $INTERFACE -j MASQUERADE 2>/dev/null || iptables -t nat -A POSTROUTING -o $INTERFACE -j MASQUERADE"
            su -c "iptables -P FORWARD ACCEPT"
            
            echo "$target_ip $port $proto" >> "$PORTS_DB"
            
            echo -e "\n${GREEN}Port forwarding active!${NC}"
            
            if [ $PUBLIC_REACHABLE -eq 1 ]; then
                echo -e "Public access: ${CYAN}$PUBLIC_IP:$port${NC}"
            else
                echo -e "Local access: ${CYAN}$LOCAL_IP:$port${NC}"
            fi
            ;;
            
        3)
            # List forwards
            echo -e "\n${YELLOW}Active Port Forwards:${NC}\n"
            
            if [ -s "$PORTS_DB" ]; then
                while read line; do
                    [ -z "$line" ] && continue
                    local ip=$(echo $line | cut -d' ' -f1)
                    local port=$(echo $line | cut -d' ' -f2)
                    local proto=$(echo $line | cut -d' ' -f3)
                    
                    echo -e "${CYAN}Port $port ($proto)${NC} -> ${WHITE}$ip${NC}"
                    
                    if [ $PUBLIC_REACHABLE -eq 1 ]; then
                        echo -e "  Public: ${GREEN}$PUBLIC_IP:$port${NC}"
                    else
                        echo -e "  Local: ${GREEN}$LOCAL_IP:$port${NC}"
                    fi
                done < "$PORTS_DB"
            else
                echo -e "${RED}No active forwards${NC}"
            fi
            ;;
            
        4)
            # Remove forward
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
                    su -c "iptables -t nat -D PREROUTING -i $INTERFACE -p tcp --dport $port -j REDIRECT --to-port $port 2>/dev/null"
                    su -c "iptables -t nat -D PREROUTING -i $INTERFACE -p udp --dport $port -j REDIRECT --to-port $port 2>/dev/null"
                else
                    su -c "iptables -t nat -D PREROUTING -i $INTERFACE -p tcp --dport $port -j DNAT --to-destination $ip:$port 2>/dev/null"
                    su -c "iptables -t nat -D PREROUTING -i $INTERFACE -p udp --dport $port -j DNAT --to-destination $ip:$port 2>/dev/null"
                    su -c "iptables -D FORWARD -p tcp -d $ip --dport $port -j ACCEPT 2>/dev/null"
                    su -c "iptables -D FORWARD -p udp -d $ip --dport $port -j ACCEPT 2>/dev/null"
                fi
                
                sed -i "/^$ip $port $proto$/d" "$PORTS_DB"
                echo -e "${GREEN}[✓] Removed${NC}"
            fi
            ;;
            
        5)
            # Test port
            echo -e "\n${YELLOW}Test Port${NC}"
            read -p "Port number to test: " test_port
            
            echo -e "\n${YELLOW}Testing port $test_port...${NC}"
            
            # Test local
            if timeout 1 nc -zv "$LOCAL_IP" "$test_port" &>/dev/null; then
                echo -e "${GREEN}[✓] Port $test_port is OPEN on $LOCAL_IP${NC}"
            else
                echo -e "${RED}[✗] Port $test_port is CLOSED on $LOCAL_IP${NC}"
            fi
            
            # Test from localhost
            if timeout 1 nc -zv "127.0.0.1" "$test_port" &>/dev/null; then
                echo -e "${GREEN}[✓] Port $test_port is OPEN on localhost${NC}"
            fi
            ;;
    esac
    
    read -p $'\n'"Press Enter..."
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
    echo -e "${GREEN}Local IP: $LOCAL_IP${NC}"
    echo -e "${GREEN}Public IP: $PUBLIC_IP${NC}"
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
        
        tput cup 10 0
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
# SPEED CONTROL
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
        echo -e "${CYAN}2.${NC} Port Forwarding (Public)"
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
    
    echo -e "${WHITE}${BOLD}Hotspot Manager v7.0${NC}"
    echo -e "${YELLOW}Public Access Edition${NC}\n"
    
    echo -e "${CYAN}Features:${NC}"
    echo -e "${GREEN}✓${NC} Public IP detection & testing"
    echo -e "${GREEN}✓${NC} Real port forwarding"
    echo -e "${GREEN}✓${NC} Minecraft server support"
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
        echo -e "${YELLOW}Local IP:${NC}   ${GREEN}${LOCAL_IP:-Not detected}${NC}"
        echo -e "${YELLOW}Public IP:${NC}  ${GREEN}${PUBLIC_IP:-Checking...}${NC}"
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
    get_public_ip
    
    echo -e "${GREEN}[✓] Ready${NC}\n"
    read -p "Press Enter to continue..."
    
    main_menu
}

# RUN
main "$@"
