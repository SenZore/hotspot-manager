#!/data/data/com.termux/files/usr/bin/bash

# ═══════════════════════════════════════════════════
# TERMUX HOTSPOT MANAGER v5.0 - FIXED
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
PORTS_DB="$CONFIG_DIR/ports.db"
DEVICE_CACHE="$CONFIG_DIR/devices.cache"

# Global vars
ROOT=0
INTERFACE="wlan0"
MY_IP=""
PUBLIC_IP=""

# ═══════════════════════════════════════════════════
# FAST BANNER
# ═══════════════════════════════════════════════════
banner() {
    clear
    echo -e "${CYAN}═══════════════════════════════════════════════════${NC}"
    echo -e "${WHITE}${BOLD}         HOTSPOT MANAGER v5.0${NC}"
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
    
    for pkg in iproute2 net-tools bc iptables ncurses-utils curl; do
        if ! dpkg -s "$pkg" &>/dev/null; then
            echo -e "${YELLOW}Installing $pkg...${NC}"
            pkg install -y "$pkg" &>/dev/null
        fi
    done
    
    echo -e "${GREEN}[✓] Dependencies ready${NC}"
}

# ═══════════════════════════════════════════════════
# DETECT INTERFACE AND IPs
# ═══════════════════════════════════════════════════
detect_interface() {
    [ $ROOT -eq 0 ] && return
    
    # Find active tethering interface
    for iface in ap0 swlan0 wlan0 rndis0; do
        if su -c "ip addr show $iface 2>/dev/null | grep -q 'inet '" 2>/dev/null; then
            INTERFACE="$iface"
            MY_IP=$(su -c "ip addr show $iface 2>/dev/null | grep 'inet ' | awk '{print \$2}' | cut -d/ -f1")
            break
        fi
    done
    
    # Get public IP (your actual internet IP)
    PUBLIC_IP=$(curl -s ifconfig.me 2>/dev/null || curl -s icanhazip.com 2>/dev/null || echo "Unknown")
}

# ═══════════════════════════════════════════════════
# SIMPLIFIED DEVICE NAME
# ═══════════════════════════════════════════════════
get_device_name() {
    local ip="$1"
    
    # Check cache first
    local cached=$(grep "^$ip " "$DEVICE_CACHE" 2>/dev/null | cut -d' ' -f2-)
    if [ -n "$cached" ]; then
        echo "$cached"
        return
    fi
    
    local name="Device"
    
    if [ $ROOT -eq 1 ]; then
        # Quick DHCP check only
        name=$(su -c "cat /data/misc/dhcp/dnsmasq.leases 2>/dev/null | grep '$ip' | awk '{print \$4}'" | head -1)
        [ -z "$name" ] || [ "$name" = "*" ] && name="Device-$ip"
    fi
    
    # Cache it
    echo "$ip $name" >> "$DEVICE_CACHE"
    echo "$name"
}

# ═══════════════════════════════════════════════════
# INIT CONFIG
# ═══════════════════════════════════════════════════
init_config() {
    mkdir -p "$CONFIG_DIR"
    touch "$CLIENTS_DB" "$BLOCKED_DB" "$PORTS_DB" "$DEVICE_CACHE"
    [ ! -f "$CONFIG_FILE" ] && echo "SPEED_LIMIT=0" > "$CONFIG_FILE"
    
    # Clean cache
    if [ -f "$DEVICE_CACHE" ]; then
        tail -50 "$DEVICE_CACHE" > "$DEVICE_CACHE.tmp" 2>/dev/null
        mv "$DEVICE_CACHE.tmp" "$DEVICE_CACHE" 2>/dev/null
    fi
}

# ═══════════════════════════════════════════════════
# GET ALL CLIENTS AT ONCE - OPTIMIZED
# ═══════════════════════════════════════════════════
get_all_clients() {
    [ $ROOT -eq 0 ] && return
    
    detect_interface
    
    # Get all clients in one go
    su -c "cat /proc/net/arp 2>/dev/null" | grep "$INTERFACE" | grep -v "00:00:00:00:00:00" | grep "0x2\|0x0" | awk '{print $1}'
}

# ═══════════════════════════════════════════════════
# SHOW CLIENT LIST - FORMATTED
# ═══════════════════════════════════════════════════
show_clients() {
    local clients=$(get_all_clients)
    
    if [ -z "$clients" ]; then
        echo -e "${RED}No devices connected${NC}"
        return 1
    fi
    
    echo -e "${YELLOW}╔═══════╦═════════════════╦═══════════════╦════════════╗${NC}"
    echo -e "${YELLOW}║  No.  ║       IP        ║   Device Name ║    Speed   ║${NC}"
    echo -e "${YELLOW}╠═══════╬═════════════════╬═══════════════╬════════════╣${NC}"
    
    local count=1
    while read ip; do
        [ -z "$ip" ] && continue
        
        local name=$(get_device_name "$ip")
        local limit=$(grep "^$ip " "$CLIENTS_DB" 2>/dev/null | cut -d' ' -f2)
        [ -z "$limit" ] || [ "$limit" = "0" ] && limit="Unlimited" || limit="${limit} KB/s"
        
        printf "${CYAN}║  %2d.  ║${NC} ${WHITE}%-15s${NC} ${CYAN}║${NC} ${GREEN}%-13s${NC} ${CYAN}║${NC} ${YELLOW}%-10s${NC} ${CYAN}║${NC}\n" \
            "$count" "$ip" "${name:0:13}" "$limit"
        
        ((count++))
    done <<< "$clients"
    
    echo -e "${YELLOW}╚═══════╩═════════════════╩═══════════════╩════════════╝${NC}"
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
# REALTIME MONITOR - CLEAN VERSION
# ═══════════════════════════════════════════════════
monitor_stats() {
    banner
    echo -e "${CYAN}═══════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}${BOLD}        REAL-TIME MONITOR${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════${NC}\n"
    
    detect_interface
    echo -e "${GREEN}Interface: $INTERFACE${NC}"
    echo -e "${GREEN}Hotspot IP: $MY_IP${NC}"
    echo -e "${GREEN}Public IP: $PUBLIC_IP${NC}"
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
        tput cup 9 0
        tput ed
        
        echo -e "${GREEN}╔════════════════════════════════════════════════╗${NC}"
        echo -e "${GREEN}║${NC} ${BOLD}NETWORK ACTIVITY${NC}"
        echo -e "${GREEN}╠════════════════════════════════════════════════╣${NC}"
        echo -e "${GREEN}║${NC} ↓ Download: ${CYAN}$rx_rate KB/s${NC}"
        echo -e "${GREEN}║${NC} ↑ Upload:   ${CYAN}$tx_rate KB/s${NC}"
        echo -e "${GREEN}╠════════════════════════════════════════════════╣${NC}"
        echo -e "${GREEN}║${NC} Total Down: ${PURPLE}$((rx/1048576)) MB${NC}"
        echo -e "${GREEN}║${NC} Total Up:   ${PURPLE}$((tx/1048576)) MB${NC}"
        echo -e "${GREEN}╚════════════════════════════════════════════════╝${NC}"
        
        if [ $ROOT -eq 1 ]; then
            echo -e "\n${YELLOW}Connected Devices:${NC}"
            
            local clients=$(get_all_clients)
            if [ -n "$clients" ]; then
                local count=1
                while read ip; do
                    [ -z "$ip" ] && continue
                    
                    local name=$(get_device_name "$ip")
                    local limit=$(grep "^$ip " "$CLIENTS_DB" 2>/dev/null | cut -d' ' -f2)
                    [ -z "$limit" ] || [ "$limit" = "0" ] && limit="∞" || limit="${limit}KB/s"
                    
                    local ports=$(grep "^$ip " "$PORTS_DB" 2>/dev/null | wc -l)
                    [ $ports -gt 0 ] && ports=" [${ports} ports]" || ports=""
                    
                    printf "  ${CYAN}%2d.${NC} %-15s │ ${WHITE}%-12s${NC} │ ${YELLOW}%-8s${NC}${PURPLE}%s${NC}\n" \
                        "$count" "$ip" "${name:0:12}" "$limit" "$ports"
                    ((count++))
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
# PORT FORWARDING - PUBLIC IP ACCESS
# ═══════════════════════════════════════════════════
port_forward() {
    [ $ROOT -eq 0 ] && echo -e "${RED}Root required${NC}" && return
    
    banner
    echo -e "${CYAN}═══════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}${BOLD}     PUBLIC PORT FORWARDING${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════${NC}\n"
    
    detect_interface
    
    echo -e "${YELLOW}Your Public IP: ${GREEN}$PUBLIC_IP${NC}"
    echo -e "${YELLOW}Hotspot IP: ${GREEN}$MY_IP${NC}"
    echo -e "${WHITE}Share your public IP with friends!${NC}\n"
    
    echo -e "${CYAN}1.${NC} Open Port (Make server public)"
    echo -e "${CYAN}2.${NC} Close Port"
    echo -e "${CYAN}3.${NC} List Open Ports"
    echo -e "${CYAN}4.${NC} Minecraft Server (25565)"
    echo -e "${CYAN}5.${NC} Web Server (80, 8080)"
    echo -e "${CYAN}6.${NC} Custom Game Server"
    echo -e "${CYAN}0.${NC} Back"
    
    read -p $'\n'"Choose: " opt
    
    case $opt in
        1)
            echo -e "\n${YELLOW}Which device hosts the server?${NC}\n"
            
            echo -e "${CYAN}1.${NC} This device (Termux)"
            echo -e "${CYAN}2.${NC} Connected device"
            
            read -p $'\n'"Choose: " host_choice
            
            local target_ip=""
            
            if [ "$host_choice" = "1" ]; then
                target_ip="127.0.0.1"
                echo -e "\n${GREEN}Opening port for this device${NC}"
            else
                local clients=$(get_all_clients)
                [ -z "$clients" ] && echo -e "${RED}No clients${NC}" && read -p "Press Enter..." && return
                
                echo -e "\n${YELLOW}Select server device:${NC}\n"
                local -a list
                local i=1
                
                while read ip; do
                    [ -z "$ip" ] && continue
                    list[$i]="$ip"
                    local name=$(get_device_name "$ip")
                    printf "${CYAN}%2d.${NC} %-15s │ ${WHITE}%s${NC}\n" $i "$ip" "$name"
                    ((i++))
                done <<< "$clients"
                
                read -p $'\n'"Select [1-$((i-1))]: " sel
                
                if [ "$sel" -ge 1 ] && [ "$sel" -lt "$i" ]; then
                    target_ip="${list[$sel]}"
                else
                    return
                fi
            fi
            
            read -p "Port number: " port
            read -p "Protocol (tcp/udp/both) [tcp]: " proto
            [ -z "$proto" ] && proto="tcp"
            
            echo -e "\n${YELLOW}Opening port $port...${NC}"
            
            # Enable IP forwarding
            su -c "sysctl -w net.ipv4.ip_forward=1" >/dev/null 2>&1
            
            # Open port for external access
            if [ "$proto" = "both" ]; then
                su -c "iptables -t nat -A PREROUTING -i $INTERFACE -p tcp --dport $port -j DNAT --to $target_ip:$port"
                su -c "iptables -t nat -A PREROUTING -i $INTERFACE -p udp --dport $port -j DNAT --to $target_ip:$port"
                su -c "iptables -A FORWARD -p tcp -d $target_ip --dport $port -j ACCEPT"
                su -c "iptables -A FORWARD -p udp -d $target_ip --dport $port -j ACCEPT"
            else
                su -c "iptables -t nat -A PREROUTING -i $INTERFACE -p $proto --dport $port -j DNAT --to $target_ip:$port"
                su -c "iptables -A FORWARD -p $proto -d $target_ip --dport $port -j ACCEPT"
            fi
            
            # Enable masquerading
            su -c "iptables -t nat -A POSTROUTING -o $INTERFACE -j MASQUERADE"
            
            # Save to database
            echo "$target_ip $port $proto" >> "$PORTS_DB"
            
            echo -e "${GREEN}╔════════════════════════════════════════════════╗${NC}"
            echo -e "${GREEN}║           PORT SUCCESSFULLY OPENED!           ║${NC}"
            echo -e "${GREEN}╠════════════════════════════════════════════════╣${NC}"
            echo -e "${GREEN}║${NC} Public Access: ${CYAN}$PUBLIC_IP:$port${NC}"
            echo -e "${GREEN}║${NC} Local Access:  ${CYAN}$MY_IP:$port${NC}"
            echo -e "${GREEN}║${NC} Protocol:      ${YELLOW}$proto${NC}"
            echo -e "${GREEN}║${NC} Target:        ${WHITE}$target_ip${NC}"
            echo -e "${GREEN}╚════════════════════════════════════════════════╝${NC}"
            echo -e "\n${YELLOW}Share ${CYAN}$PUBLIC_IP:$port${YELLOW} with your friends!${NC}"
            ;;
            
        2)
            [ ! -s "$PORTS_DB" ] && echo -e "${RED}No open ports${NC}" && read -p "Press Enter..." && return
            
            echo -e "\n${YELLOW}Open Ports:${NC}\n"
            local i=1
            local -a list
            
            while read line; do
                [ -z "$line" ] && continue
                list[$i]="$line"
                local ip=$(echo $line | cut -d' ' -f1)
                local port=$(echo $line | cut -d' ' -f2)
                local proto=$(echo $line | cut -d' ' -f3)
                
                printf "${CYAN}%2d.${NC} Port %-5s (%s) → %s\n" $i "$port" "$proto" "$ip"
                ((i++))
            done < "$PORTS_DB"
            
            read -p $'\n'"Close port [1-$((i-1))]: " sel
            
            if [ "$sel" -ge 1 ] && [ "$sel" -lt "$i" ]; then
                local rule="${list[$sel]}"
                local ip=$(echo $rule | cut -d' ' -f1)
                local port=$(echo $rule | cut -d' ' -f2)
                local proto=$(echo $rule | cut -d' ' -f3)
                
                echo -e "\n${YELLOW}Closing port $port...${NC}"
                
                if [ "$proto" = "both" ]; then
                    su -c "iptables -t nat -D PREROUTING -i $INTERFACE -p tcp --dport $port -j DNAT --to $ip:$port 2>/dev/null"
                    su -c "iptables -t nat -D PREROUTING -i $INTERFACE -p udp --dport $port -j DNAT --to $ip:$port 2>/dev/null"
                    su -c "iptables -D FORWARD -p tcp -d $ip --dport $port -j ACCEPT 2>/dev/null"
                    su -c "iptables -D FORWARD -p udp -d $ip --dport $port -j ACCEPT 2>/dev/null"
                else
                    su -c "iptables -t nat -D PREROUTING -i $INTERFACE -p $proto --dport $port -j DNAT --to $ip:$port 2>/dev/null"
                    su -c "iptables -D FORWARD -p $proto -d $ip --dport $port -j ACCEPT 2>/dev/null"
                fi
                
                sed -i "/^$ip $port $proto$/d" "$PORTS_DB"
                echo -e "${GREEN}[✓] Port closed${NC}"
            fi
            ;;
            
        3)
            echo -e "\n${YELLOW}╔════════════════════════════════════════════════╗${NC}"
            echo -e "${YELLOW}║              OPEN PORTS                       ║${NC}"
            echo -e "${YELLOW}╚════════════════════════════════════════════════╝${NC}\n"
            
            if [ -s "$PORTS_DB" ]; then
                while read line; do
                    [ -z "$line" ] && continue
                    local ip=$(echo $line | cut -d' ' -f1)
                    local port=$(echo $line | cut -d' ' -f2)
                    local proto=$(echo $line | cut -d' ' -f3)
                    
                    echo -e "${CYAN}•${NC} ${GREEN}$PUBLIC_IP:$port${NC} → $ip ($proto)"
                done < "$PORTS_DB"
            else
                echo -e "${RED}No ports open${NC}"
            fi
            ;;
            
        4)
            # Quick Minecraft setup
            echo -e "\n${YELLOW}Setting up Minecraft server...${NC}"
            
            echo -e "${CYAN}1.${NC} Host on this device (Termux)"
            echo -e "${CYAN}2.${NC} Host on connected device"
            
            read -p $'\n'"Choose: " mc_choice
            
            local mc_ip=""
            if [ "$mc_choice" = "1" ]; then
                mc_ip="127.0.0.1"
            else
                local clients=$(get_all_clients)
                [ -z "$clients" ] && echo -e "${RED}No clients${NC}" && read -p "Press Enter..." && return
                
                echo -e "\n${YELLOW}Select Minecraft host:${NC}\n"
                local -a list
                local i=1
                
                while read ip; do
                    [ -z "$ip" ] && continue
                    list[$i]="$ip"
                    local name=$(get_device_name "$ip")
                    printf "${CYAN}%2d.${NC} %-15s │ ${WHITE}%s${NC}\n" $i "$ip" "$name"
                    ((i++))
                done <<< "$clients"
                
                read -p $'\n'"Select [1-$((i-1))]: " sel
                
                if [ "$sel" -ge 1 ] && [ "$sel" -lt "$i" ]; then
                    mc_ip="${list[$sel]}"
                else
                    return
                fi
            fi
            
            echo -e "\n${YELLOW}Opening Minecraft port...${NC}"
            
            su -c "sysctl -w net.ipv4.ip_forward=1" >/dev/null 2>&1
            
            # Minecraft uses TCP and UDP
            su -c "iptables -t nat -A PREROUTING -i $INTERFACE -p tcp --dport 25565 -j DNAT --to $mc_ip:25565"
            su -c "iptables -t nat -A PREROUTING -i $INTERFACE -p udp --dport 25565 -j DNAT --to $mc_ip:25565"
            su -c "iptables -A FORWARD -p tcp -d $mc_ip --dport 25565 -j ACCEPT"
            su -c "iptables -A FORWARD -p udp -d $mc_ip --dport 25565 -j ACCEPT"
            su -c "iptables -t nat -A POSTROUTING -o $INTERFACE -j MASQUERADE"
            
            echo "$mc_ip 25565 both" >> "$PORTS_DB"
            
            echo -e "${GREEN}╔════════════════════════════════════════════════╗${NC}"
            echo -e "${GREEN}║       MINECRAFT SERVER READY!                 ║${NC}"
            echo -e "${GREEN}╠════════════════════════════════════════════════╣${NC}"
            echo -e "${GREEN}║${NC} Server IP: ${CYAN}$PUBLIC_IP:25565${NC}"
            echo -e "${GREEN}║${NC} Share this with friends!                      ${GREEN}║${NC}"
            echo -e "${GREEN}╚════════════════════════════════════════════════╝${NC}"
            ;;
            
        5)
            # Web server setup
            echo -e "\n${YELLOW}Setting up web server...${NC}"
            
            echo -e "${CYAN}1.${NC} Host on this device"
            echo -e "${CYAN}2.${NC} Host on connected device"
            
            read -p $'\n'"Choose: " web_choice
            
            local web_ip=""
            if [ "$web_choice" = "1" ]; then
                web_ip="127.0.0.1"
            else
                local clients=$(get_all_clients)
                [ -z "$clients" ] && echo -e "${RED}No clients${NC}" && read -p "Press Enter..." && return
                
                echo -e "\n${YELLOW}Select web host:${NC}\n"
                local -a list
                local i=1
                
                while read ip; do
                    [ -z "$ip" ] && continue
                    list[$i]="$ip"
                    local name=$(get_device_name "$ip")
                    printf "${CYAN}%2d.${NC} %-15s │ ${WHITE}%s${NC}\n" $i "$ip" "$name"
                    ((i++))
                done <<< "$clients"
                
                read -p $'\n'"Select [1-$((i-1))]: " sel
                
                if [ "$sel" -ge 1 ] && [ "$sel" -lt "$i" ]; then
                    web_ip="${list[$sel]}"
                else
                    return
                fi
            fi
            
            read -p "Port (80/8080/custom) [8080]: " web_port
            [ -z "$web_port" ] && web_port="8080"
            
            echo -e "\n${YELLOW}Opening web server port...${NC}"
            
            su -c "sysctl -w net.ipv4.ip_forward=1" >/dev/null 2>&1
            su -c "iptables -t nat -A PREROUTING -i $INTERFACE -p tcp --dport $web_port -j DNAT --to $web_ip:$web_port"
            su -c "iptables -A FORWARD -p tcp -d $web_ip --dport $web_port -j ACCEPT"
            su -c "iptables -t nat -A POSTROUTING -o $INTERFACE -j MASQUERADE"
            
            echo "$web_ip $web_port tcp" >> "$PORTS_DB"
            
            echo -e "${GREEN}╔════════════════════════════════════════════════╗${NC}"
            echo -e "${GREEN}║         WEB SERVER READY!                     ║${NC}"
            echo -e "${GREEN}╠════════════════════════════════════════════════╣${NC}"
            echo -e "${GREEN}║${NC} URL: ${CYAN}http://$PUBLIC_IP:$web_port${NC}"
            echo -e "${GREEN}╚════════════════════════════════════════════════╝${NC}"
            ;;
            
        6)
            # Custom game server
            echo -e "\n${YELLOW}Popular Game Ports:${NC}"
            echo -e "${CYAN}• Minecraft:${NC} 25565 (TCP/UDP)"
            echo -e "${CYAN}• Terraria:${NC} 7777 (TCP)"
            echo -e "${CYAN}• CS:GO:${NC} 27015 (TCP/UDP)"
            echo -e "${CYAN}• Rust:${NC} 28015 (TCP/UDP)"
            echo -e "${CYAN}• Valheim:${NC} 2456-2457 (TCP/UDP)"
            echo -e "${CYAN}• Among Us:${NC} 22023 (UDP)"
            
            read -p $'\n'"Enter game port: " game_port
            read -p "Protocol (tcp/udp/both): " game_proto
            
            echo -e "\n${CYAN}1.${NC} Host on this device"
            echo -e "${CYAN}2.${NC} Host on connected device"
            
            read -p $'\n'"Choose: " game_choice
            
            local game_ip=""
            if [ "$game_choice" = "1" ]; then
                game_ip="127.0.0.1"
            else
                local clients=$(get_all_clients)
                [ -z "$clients" ] && echo -e "${RED}No clients${NC}" && read -p "Press Enter..." && return
                
                echo -e "\n${YELLOW}Select game host:${NC}\n"
                local -a list
                local i=1
                
                while read ip; do
                    [ -z "$ip" ] && continue
                    list[$i]="$ip"
                    local name=$(get_device_name "$ip")
                    printf "${CYAN}%2d.${NC} %-15s │ ${WHITE}%s${NC}\n" $i "$ip" "$name"
                    ((i++))
                done <<< "$clients"
                
                read -p $'\n'"Select [1-$((i-1))]: " sel
                
                if [ "$sel" -ge 1 ] && [ "$sel" -lt "$i" ]; then
                    game_ip="${list[$sel]}"
                else
                    return
                fi
            fi
            
            echo -e "\n${YELLOW}Opening game port...${NC}"
            
            su -c "sysctl -w net.ipv4.ip_forward=1" >/dev/null 2>&1
            
            if [ "$game_proto" = "both" ]; then
                su -c "iptables -t nat -A PREROUTING -i $INTERFACE -p tcp --dport $game_port -j DNAT --to $game_ip:$game_port"
                su -c "iptables -t nat -A PREROUTING -i $INTERFACE -p udp --dport $game_port -j DNAT --to $game_ip:$game_port"
                su -c "iptables -A FORWARD -p tcp -d $game_ip --dport $game_port -j ACCEPT"
                su -c "iptables -A FORWARD -p udp -d $game_ip --dport $game_port -j ACCEPT"
            else
                su -c "iptables -t nat -A PREROUTING -i $INTERFACE -p $game_proto --dport $game_port -j DNAT --to $game_ip:$game_port"
                su -c "iptables -A FORWARD -p $game_proto -d $game_ip --dport $game_port -j ACCEPT"
            fi
            
            su -c "iptables -t nat -A POSTROUTING -o $INTERFACE -j MASQUERADE"
            
            echo "$game_ip $game_port $game_proto" >> "$PORTS_DB"
            
            echo -e "${GREEN}╔════════════════════════════════════════════════╗${NC}"
            echo -e "${GREEN}║         GAME SERVER READY!                    ║${NC}"
            echo -e "${GREEN}╠════════════════════════════════════════════════╣${NC}"
            echo -e "${GREEN}║${NC} Connect: ${CYAN}$PUBLIC_IP:$game_port${NC}"
            echo -e "${GREEN}╚════════════════════════════════════════════════╝${NC}"
            ;;
    esac
    
    read -p $'\n'"Press Enter..."
}

# ═══════════════════════════════════════════════════
# SPEED CONTROL - FIXED
# ═══════════════════════════════════════════════════
set_speed() {
    [ $ROOT -eq 0 ] && echo -e "${RED}Root required${NC}" && return
    
    banner
    echo -e "${CYAN}═══════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}${BOLD}          SPEED CONTROL${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════${NC}\n"
    
    show_clients || { read -p "Press Enter..."; return; }
    
    local clients=$(get_all_clients)
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
            apply_limit "${list[$j]}"
        done
    elif [ "$sel" -ge 1 ] && [ "$sel" -lt "$i" ]; then
        apply_limit "${list[$sel]}"
    fi
    
    read -p "Press Enter..."
}

# ═══════════════════════════════════════════════════
# BLOCK/UNBLOCK/KICK - SIMPLIFIED
# ═══════════════════════════════════════════════════
block_client() {
    [ $ROOT -eq 0 ] && echo -e "${RED}Root required${NC}" && return
    
    banner
    echo -e "${CYAN}═══════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}${BOLD}          BLOCK DEVICE${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════${NC}\n"
    
    show_clients || { read -p "Press Enter..."; return; }
    
    local clients=$(get_all_clients)
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
        local name=$(get_device_name "$ip")
        printf "${CYAN}%2d.${NC} %-15s │ ${WHITE}%s${NC}\n" $i "$ip" "$name"
        ((i++))
    done < "$BLOCKED_DB"
    
    read -p $'\n'"Select [1-$((i-1))]: " sel
    
    if [ "$sel" -ge 1 ] && [ "$sel" -lt "$i" ]; then
        local ip="${list[$sel]}"
        
        echo -e "\n${YELLOW}Unblocking $ip...${NC}"
        su -c "iptables -D FORWARD -s $ip -j DROP 2>/dev/null"
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
    
    local clients=$(get_all_clients)
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
        echo -e "${CYAN}2.${NC} Port Forwarding (Public Access)"
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
    
    echo -e "${WHITE}${BOLD}Hotspot Manager v5.0${NC}"
    echo -e "${YELLOW}Public Server Hosting Edition${NC}\n"
    
    echo -e "${CYAN}Features:${NC}"
    echo -e "${GREEN}✓${NC} Public IP port forwarding"
    echo -e "${GREEN}✓${NC} Host servers (Minecraft, Web, etc)"
    echo -e "${GREEN}✓${NC} Speed control per device"
    echo -e "${GREEN}✓${NC} Clean device listing"
    echo -e "${GREEN}✓${NC} Optimized performance"
    
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
        echo -e "${YELLOW}Hotspot IP:${NC} ${GREEN}${MY_IP:-Not detected}${NC}"
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
