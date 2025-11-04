#!/data/data/com.termux/files/usr/bin/bash

# ═══════════════════════════════════════════════════
# TERMUX HOTSPOT MANAGER v4.0 - ENHANCED
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
GATEWAY_IP=""

# ═══════════════════════════════════════════════════
# FAST BANNER
# ═══════════════════════════════════════════════════
banner() {
    clear
    echo -e "${CYAN}═══════════════════════════════════════════════════${NC}"
    echo -e "${WHITE}${BOLD}         HOTSPOT MANAGER v4.0${NC}"
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
    
    for pkg in iproute2 net-tools bc iptables ncurses-utils dnsutils; do
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
            # Get gateway IP
            GATEWAY_IP=$(su -c "ip addr show $iface 2>/dev/null | grep 'inet ' | awk '{print \$2}' | cut -d/ -f1")
            return
        fi
    done
}

# ═══════════════════════════════════════════════════
# GET REAL DEVICE NAME (ENHANCED)
# ═══════════════════════════════════════════════════
get_device_name() {
    local ip="${1:-}"
    local mac="${2:-}"
    local name=""
    
    [ -z "$ip" ] || [ -z "$mac" ] && echo "Unknown" && return
    
    # Check cache first
    local cached=$(grep "^$mac " "$DEVICE_CACHE" 2>/dev/null | cut -d' ' -f2-)
    if [ -n "$cached" ]; then
        echo "$cached"
        return
    fi
    
    if [ $ROOT -eq 1 ]; then
        # Method 1: Check DHCP leases for hostname
        name=$(su -c "cat /data/misc/dhcp/dnsmasq.leases 2>/dev/null | grep -i '$mac' | awk '{print \$4}'" | head -1)
        
        # Method 2: Check dumpsys wifi for device info
        if [ -z "$name" ] || [ "$name" = "*" ]; then
            local wifi_info=$(su -c "dumpsys wifi 2>/dev/null | grep -B5 -A5 '$mac'" | head -20)
            
            # Try to get device name from WiFi info
            name=$(echo "$wifi_info" | grep -E "mDeviceName|DeviceName" | cut -d'=' -f2 | tr -d ' ' | head -1)
            
            # Try hostname
            if [ -z "$name" ]; then
                name=$(echo "$wifi_info" | grep -E "hostname" | cut -d':' -f2 | tr -d ' ' | head -1)
            fi
        fi
        
        # Method 3: Try reverse DNS
        if [ -z "$name" ] || [ "$name" = "*" ]; then
            name=$(su -c "timeout 0.5 nslookup $ip 2>/dev/null" | grep "name =" | awk '{print $4}' | sed 's/\.local\.//;s/\.$//' | head -1)
        fi
        
        # Method 4: Check connected devices info
        if [ -z "$name" ] || [ "$name" = "*" ]; then
            name=$(su -c "dumpsys connectivity 2>/dev/null | grep -A2 '$ip'" | grep "iface" | cut -d'"' -f2 | head -1)
        fi
        
        # Method 5: Try to get from netd
        if [ -z "$name" ] || [ "$name" = "*" ]; then
            name=$(su -c "dumpsys netd 2>/dev/null | grep -A1 '$mac'" | tail -1 | awk '{print $1}')
        fi
    fi
    
    # If still no name, use vendor identification
    if [ -z "$name" ] || [ "$name" = "*" ] || [ "$name" = "Unknown" ]; then
        local prefix="${mac:0:8}"
        case "${prefix^^}" in
            "00:0C:29"|"00:50:56") name="VMware-Device" ;;
            "2C:4D:54") name="ASUS-Device" ;;
            "38:D5:47"|"40:B0:76"|"84:11:9E") name="Samsung-Galaxy" ;;
            "3C:06:30"|"50:8F:4C"|"7C:1D:D9") name="Xiaomi-Device" ;;
            "44:01:BB"|"E4:C2:39"|"AC:56:1C") name="OPPO/Realme" ;;
            "50:C7:BF") name="TP-Link" ;;
            "74:60:FA"|"DC:72:23") name="OnePlus" ;;
            "8C:79:67"|"48:01:C5") name="Huawei" ;;
            "94:65:2D"|"C0:EE:FB") name="OnePlus" ;;
            "A4:C6:4F"|"10:5A:17") name="Vivo" ;;
            "DC:72:9B"|"84:F0:29") name="Infinix" ;;
            "F8:E9:4E"|"AC:EE:9E") name="iPhone" ;;
            *) name="Android-Device" ;;
        esac
    fi
    
    # Cache the result
    echo "$mac $name" >> "$DEVICE_CACHE"
    
    # Clean up name
    name=$(echo "$name" | sed 's/[^a-zA-Z0-9-]/-/g' | sed 's/--*/-/g' | sed 's/^-//;s/-$//')
    [ -z "$name" ] && name="Device"
    
    echo "$name"
}

# ═══════════════════════════════════════════════════
# INIT CONFIG
# ═══════════════════════════════════════════════════
init_config() {
    mkdir -p "$CONFIG_DIR"
    touch "$CLIENTS_DB" "$BLOCKED_DB" "$PORTS_DB" "$DEVICE_CACHE"
    [ ! -f "$CONFIG_FILE" ] && echo "SPEED_LIMIT=0" > "$CONFIG_FILE"
    
    # Clean old cache entries (older than 1 day)
    if [ -f "$DEVICE_CACHE" ]; then
        local temp_cache=$(mktemp)
        tail -100 "$DEVICE_CACHE" > "$temp_cache" 2>/dev/null
        mv "$temp_cache" "$DEVICE_CACHE" 2>/dev/null
    fi
}

# ═══════════════════════════════════════════════════
# GET CLIENTS - FAST VERSION
# ═══════════════════════════════════════════════════
get_clients() {
    [ $ROOT -eq 0 ] && return
    
    detect_interface
    
    # Get from ARP with better filtering
    su -c "cat /proc/net/arp 2>/dev/null" | grep "$INTERFACE" | grep -v "00:00:00:00:00:00" | grep "0x2\|0x0" | awk '{print $1" "$4}'
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
# REALTIME MONITOR - ENHANCED
# ═══════════════════════════════════════════════════
monitor_stats() {
    banner
    echo -e "${CYAN}═══════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}${BOLD}        REAL-TIME MONITOR${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════${NC}\n"
    
    detect_interface
    echo -e "${GREEN}Interface: $INTERFACE${NC}"
    echo -e "${GREEN}Gateway: $GATEWAY_IP${NC}"
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
    local prev_time=$(date +%s%N)
    
    # Client bandwidth tracking
    declare -A client_rx client_tx
    
    while true; do
        sleep 1
        
        local curr_time=$(date +%s%N)
        local time_diff=$((curr_time - prev_time))
        
        local rx=$(cat $stats/rx_bytes)
        local tx=$(cat $stats/tx_bytes)
        
        local rx_rate=$(( (rx - prev_rx) / 1024 ))
        local tx_rate=$(( (tx - prev_tx) / 1024 ))
        
        [ $rx_rate -lt 0 ] && rx_rate=0
        [ $tx_rate -lt 0 ] && tx_rate=0
        
        # Calculate Mbps if speed is high
        local rx_display="$rx_rate KB/s"
        local tx_display="$tx_rate KB/s"
        
        if [ $rx_rate -gt 1024 ]; then
            rx_display="$(echo "scale=1; $rx_rate/1024" | bc) MB/s"
        fi
        if [ $tx_rate -gt 1024 ]; then
            tx_display="$(echo "scale=1; $tx_rate/1024" | bc) MB/s"
        fi
        
        # Clear and update
        tput cup 8 0
        tput ed
        
        echo -e "${GREEN}╔════════════════════════════════════════════════╗${NC}"
        echo -e "${GREEN}║${NC} ${BOLD}NETWORK ACTIVITY${NC}"
        echo -e "${GREEN}╠════════════════════════════════════════════════╣${NC}"
        echo -e "${GREEN}║${NC} ↓ Download: ${CYAN}$rx_display${NC}"
        echo -e "${GREEN}║${NC} ↑ Upload:   ${CYAN}$tx_display${NC}"
        echo -e "${GREEN}╠════════════════════════════════════════════════╣${NC}"
        echo -e "${GREEN}║${NC} Total Down: ${PURPLE}$((rx/1048576)) MB${NC}"
        echo -e "${GREEN}║${NC} Total Up:   ${PURPLE}$((tx/1048576)) MB${NC}"
        echo -e "${GREEN}╚════════════════════════════════════════════════╝${NC}"
        
        if [ $ROOT -eq 1 ]; then
            echo -e "\n${YELLOW}${BOLD}CONNECTED DEVICES:${NC}"
            echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
            
            local clients=$(get_clients)
            if [ -n "$clients" ]; then
                local count=0
                while read ip mac; do
                    [ -z "$ip" ] && continue
                    ((count++))
                    
                    local name=$(get_device_name "$ip" "$mac")
                    local limit=$(grep "^$ip " "$CLIENTS_DB" 2>/dev/null | cut -d' ' -f2)
                    [ -z "$limit" ] || [ "$limit" = "0" ] && limit="Unlimited" || limit="${limit}KB/s"
                    
                    # Port forwards for this IP
                    local ports=$(grep "^$ip " "$PORTS_DB" 2>/dev/null | cut -d' ' -f2- | tr '\n' ',' | sed 's/,$//')
                    [ -z "$ports" ] && ports="None" || ports="[$ports]"
                    
                    printf "${CYAN}%2d.${NC} ${WHITE}%-15s${NC} │ ${GREEN}%-15s${NC}\n" "$count" "$ip" "$name"
                    printf "    Speed: ${YELLOW}%-10s${NC} │ Ports: ${PURPLE}%s${NC}\n" "$limit" "$ports"
                done <<< "$clients"
            else
                echo -e "${RED}  No devices connected${NC}"
            fi
            
            echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        fi
        
        prev_rx=$rx
        prev_tx=$tx
        prev_time=$curr_time
    done
}

# ═══════════════════════════════════════════════════
# PORT FORWARDING
# ═══════════════════════════════════════════════════
port_forward() {
    [ $ROOT -eq 0 ] && echo -e "${RED}Root required${NC}" && return
    
    banner
    echo -e "${CYAN}═══════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}${BOLD}        PORT FORWARDING${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════${NC}\n"
    
    detect_interface
    
    echo -e "${YELLOW}Gateway IP: $GATEWAY_IP${NC}\n"
    
    echo -e "${CYAN}1.${NC} Add Port Forward"
    echo -e "${CYAN}2.${NC} Remove Port Forward"
    echo -e "${CYAN}3.${NC} List Active Forwards"
    echo -e "${CYAN}4.${NC} Quick Minecraft Server (25565)"
    echo -e "${CYAN}5.${NC} Quick Web Server (80,443)"
    echo -e "${CYAN}0.${NC} Back"
    
    read -p $'\n'"Choose: " opt
    
    case $opt in
        1)
            local clients=$(get_clients)
            [ -z "$clients" ] && echo -e "${RED}No clients${NC}" && read -p "Press Enter..." && return
            
            echo -e "\n${YELLOW}Select target device:${NC}\n"
            local -a list
            local i=1
            
            while read ip mac; do
                [ -z "$ip" ] && continue
                list[$i]="$ip"
                local name=$(get_device_name "$ip" "$mac")
                printf "${CYAN}%2d.${NC} %-15s │ ${WHITE}%s${NC}\n" $i "$ip" "$name"
                ((i++))
            done <<< "$clients"
            
            read -p $'\n'"Select [1-$((i-1))]: " sel
            
            if [ "$sel" -ge 1 ] && [ "$sel" -lt "$i" ]; then
                local target_ip="${list[$sel]}"
                
                read -p "External port: " ext_port
                read -p "Internal port (same as external if empty): " int_port
                [ -z "$int_port" ] && int_port=$ext_port
                
                read -p "Protocol (tcp/udp/both) [tcp]: " proto
                [ -z "$proto" ] && proto="tcp"
                
                echo -e "\n${YELLOW}Setting up forward...${NC}"
                
                # Enable forwarding
                su -c "sysctl -w net.ipv4.ip_forward=1" >/dev/null 2>&1
                
                if [ "$proto" = "both" ]; then
                    # TCP
                    su -c "iptables -t nat -A PREROUTING -p tcp --dport $ext_port -j DNAT --to-destination $target_ip:$int_port"
                    su -c "iptables -A FORWARD -p tcp -d $target_ip --dport $int_port -j ACCEPT"
                    # UDP
                    su -c "iptables -t nat -A PREROUTING -p udp --dport $ext_port -j DNAT --to-destination $target_ip:$int_port"
                    su -c "iptables -A FORWARD -p udp -d $target_ip --dport $int_port -j ACCEPT"
                    
                    echo "$target_ip $ext_port:$int_port:both" >> "$PORTS_DB"
                else
                    su -c "iptables -t nat -A PREROUTING -p $proto --dport $ext_port -j DNAT --to-destination $target_ip:$int_port"
                    su -c "iptables -A FORWARD -p $proto -d $target_ip --dport $int_port -j ACCEPT"
                    
                    echo "$target_ip $ext_port:$int_port:$proto" >> "$PORTS_DB"
                fi
                
                # Masquerade for NAT
                su -c "iptables -t nat -A POSTROUTING -j MASQUERADE"
                
                echo -e "${GREEN}[✓] Port forward active${NC}"
                echo -e "${GREEN}External: $GATEWAY_IP:$ext_port → $target_ip:$int_port ($proto)${NC}"
            fi
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
                local rule=$(echo $line | cut -d' ' -f2)
                local ext=$(echo $rule | cut -d: -f1)
                local int=$(echo $rule | cut -d: -f2)
                local proto=$(echo $rule | cut -d: -f3)
                
                printf "${CYAN}%2d.${NC} %s:%s → %s:%s (%s)\n" $i "$GATEWAY_IP" "$ext" "$ip" "$int" "$proto"
                ((i++))
            done < "$PORTS_DB"
            
            read -p $'\n'"Remove [1-$((i-1))]: " sel
            
            if [ "$sel" -ge 1 ] && [ "$sel" -lt "$i" ]; then
                local rule="${list[$sel]}"
                local ip=$(echo $rule | cut -d' ' -f1)
                local port_rule=$(echo $rule | cut -d' ' -f2)
                local ext=$(echo $port_rule | cut -d: -f1)
                local int=$(echo $port_rule | cut -d: -f2)
                local proto=$(echo $port_rule | cut -d: -f3)
                
                echo -e "\n${YELLOW}Removing forward...${NC}"
                
                if [ "$proto" = "both" ]; then
                    su -c "iptables -t nat -D PREROUTING -p tcp --dport $ext -j DNAT --to-destination $ip:$int 2>/dev/null"
                    su -c "iptables -D FORWARD -p tcp -d $ip --dport $int -j ACCEPT 2>/dev/null"
                    su -c "iptables -t nat -D PREROUTING -p udp --dport $ext -j DNAT --to-destination $ip:$int 2>/dev/null"
                    su -c "iptables -D FORWARD -p udp -d $ip --dport $int -j ACCEPT 2>/dev/null"
                else
                    su -c "iptables -t nat -D PREROUTING -p $proto --dport $ext -j DNAT --to-destination $ip:$int 2>/dev/null"
                    su -c "iptables -D FORWARD -p $proto -d $ip --dport $int -j ACCEPT 2>/dev/null"
                fi
                
                sed -i "/^$ip $port_rule$/d" "$PORTS_DB"
                echo -e "${GREEN}[✓] Removed${NC}"
            fi
            ;;
            
        3)
            echo -e "\n${YELLOW}Active Port Forwards:${NC}\n"
            
            if [ -s "$PORTS_DB" ]; then
                while read line; do
                    [ -z "$line" ] && continue
                    local ip=$(echo $line | cut -d' ' -f1)
                    local rule=$(echo $line | cut -d' ' -f2)
                    local ext=$(echo $rule | cut -d: -f1)
                    local int=$(echo $rule | cut -d: -f2)
                    local proto=$(echo $rule | cut -d: -f3)
                    
                    echo -e "${CYAN}•${NC} $GATEWAY_IP:$ext → $ip:$int ($proto)"
                done < "$PORTS_DB"
            else
                echo -e "${RED}No active forwards${NC}"
            fi
            ;;
            
        4)
            # Quick Minecraft setup
            local clients=$(get_clients)
            [ -z "$clients" ] && echo -e "${RED}No clients${NC}" && read -p "Press Enter..." && return
            
            echo -e "\n${YELLOW}Select Minecraft server device:${NC}\n"
            local -a list
            local i=1
            
            while read ip mac; do
                [ -z "$ip" ] && continue
                list[$i]="$ip"
                local name=$(get_device_name "$ip" "$mac")
                printf "${CYAN}%2d.${NC} %-15s │ ${WHITE}%s${NC}\n" $i "$ip" "$name"
                ((i++))
            done <<< "$clients"
            
            read -p $'\n'"Select [1-$((i-1))]: " sel
            
            if [ "$sel" -ge 1 ] && [ "$sel" -lt "$i" ]; then
                local mc_ip="${list[$sel]}"
                
                echo -e "\n${YELLOW}Setting up Minecraft server...${NC}"
                
                # Enable forwarding
                su -c "sysctl -w net.ipv4.ip_forward=1" >/dev/null 2>&1
                
                # Minecraft uses TCP and UDP on 25565
                su -c "iptables -t nat -A PREROUTING -p tcp --dport 25565 -j DNAT --to-destination $mc_ip:25565"
                su -c "iptables -A FORWARD -p tcp -d $mc_ip --dport 25565 -j ACCEPT"
                su -c "iptables -t nat -A PREROUTING -p udp --dport 25565 -j DNAT --to-destination $mc_ip:25565"
                su -c "iptables -A FORWARD -p udp -d $mc_ip --dport 25565 -j ACCEPT"
                
                # Query port
                su -c "iptables -t nat -A PREROUTING -p udp --dport 25565 -j DNAT --to-destination $mc_ip:25565"
                
                # Masquerade
                su -c "iptables -t nat -A POSTROUTING -j MASQUERADE"
                
                echo "$mc_ip 25565:25565:both" >> "$PORTS_DB"
                
                echo -e "${GREEN}[✓] Minecraft server configured${NC}"
                echo -e "${GREEN}Server address: $GATEWAY_IP:25565${NC}"
                echo -e "${YELLOW}Share this IP with friends to connect!${NC}"
            fi
            ;;
            
        5)
            # Quick web server setup
            local clients=$(get_clients)
            [ -z "$clients" ] && echo -e "${RED}No clients${NC}" && read -p "Press Enter..." && return
            
            echo -e "\n${YELLOW}Select web server device:${NC}\n"
            local -a list
            local i=1
            
            while read ip mac; do
                [ -z "$ip" ] && continue
                list[$i]="$ip"
                local name=$(get_device_name "$ip" "$mac")
                printf "${CYAN}%2d.${NC} %-15s │ ${WHITE}%s${NC}\n" $i "$ip" "$name"
                ((i++))
            done <<< "$clients"
            
            read -p $'\n'"Select [1-$((i-1))]: " sel
            
            if [ "$sel" -ge 1 ] && [ "$sel" -lt "$i" ]; then
                local web_ip="${list[$sel]}"
                
                echo -e "\n${YELLOW}Setting up web server...${NC}"
                
                su -c "sysctl -w net.ipv4.ip_forward=1" >/dev/null 2>&1
                
                # HTTP
                su -c "iptables -t nat -A PREROUTING -p tcp --dport 80 -j DNAT --to-destination $web_ip:80"
                su -c "iptables -A FORWARD -p tcp -d $web_ip --dport 80 -j ACCEPT"
                
                # HTTPS
                su -c "iptables -t nat -A PREROUTING -p tcp --dport 443 -j DNAT --to-destination $web_ip:443"
                su -c "iptables -A FORWARD -p tcp -d $web_ip --dport 443 -j ACCEPT"
                
                su -c "iptables -t nat -A POSTROUTING -j MASQUERADE"
                
                echo "$web_ip 80:80:tcp" >> "$PORTS_DB"
                echo "$web_ip 443:443:tcp" >> "$PORTS_DB"
                
                echo -e "${GREEN}[✓] Web server configured${NC}"
                echo -e "${GREEN}HTTP: http://$GATEWAY_IP${NC}"
                echo -e "${GREEN}HTTPS: https://$GATEWAY_IP${NC}"
            fi
            ;;
    esac
    
    read -p $'\n'"Press Enter..."
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
        local name=$(get_device_name "$ip" "$mac")
        local limit=$(grep "^$ip " "$CLIENTS_DB" 2>/dev/null | cut -d' ' -f2)
        [ -z "$limit" ] || [ "$limit" = "0" ] && limit="Unlimited" || limit="${limit}KB/s"
        
        printf "${CYAN}%2d.${NC} %-15s │ ${WHITE}%-15s${NC} │ ${YELLOW}%s${NC}\n" $i "$ip" "$name" "$limit"
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
        local name=$(get_device_name "$ip" "$mac")
        printf "${CYAN}%2d.${NC} %-15s │ ${WHITE}%s${NC}\n" $i "$ip" "$name"
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
        local name=$(get_device_name "$ip" "$mac")
        printf "${CYAN}%2d.${NC} %-15s │ ${WHITE}%s${NC}\n" $i "$ip" "$name"
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
        local name=$(get_device_name "$ip" "$mac")
        printf "${CYAN}%2d.${NC} %-15s │ ${WHITE}%s${NC}\n" $i "$ip" "$name"
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
                    local name=$(get_device_name "$ip" "$mac")
                    local limit=$(grep "^$ip " "$CLIENTS_DB" 2>/dev/null | cut -d' ' -f2)
                    [ -z "$limit" ] || [ "$limit" = "0" ] && limit="∞" || limit="${limit}KB/s"
                    
                    printf "${CYAN}•${NC} %-15s │ ${WHITE}%-15s${NC} │ ${YELLOW}%s${NC}\n" "$ip" "$name" "$limit"
                done <<< "$clients"
            else
                echo -e "${RED}No devices connected${NC}"
            fi
        fi
        
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
    
    echo -e "${WHITE}${BOLD}Hotspot Manager v4.0${NC}"
    echo -e "${YELLOW}Enhanced Edition with Port Forwarding${NC}\n"
    
    echo -e "${CYAN}Features:${NC}"
    echo -e "${GREEN}✓${NC} Real device name detection"
    echo -e "${GREEN}✓${NC} Port forwarding (uPnP-like)"
    echo -e "${GREEN}✓${NC} Minecraft server support"
    echo -e "${GREEN}✓${NC} Speed control per device"
    echo -e "${GREEN}✓${NC} Block/Kick management"
    echo -e "${GREEN}✓${NC} Enhanced monitoring"
    
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
        echo -e "${YELLOW}Gateway:${NC}   ${GREEN}${GATEWAY_IP:-Not detected}${NC}"
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
