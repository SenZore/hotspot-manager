#!/data/data/com.termux/files/usr/bin/bash

# ═══════════════════════════════════════════════════
# TERMUX HOTSPOT MANAGER v10.0 - COMPLETE EDITION
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
TUNNEL_CONFIG="$CONFIG_DIR/tunnel.conf"

# Global vars
ROOT=0
INTERFACE="wlan0"
LOCAL_IP=""
PUBLIC_IP=""
BEHIND_CGNAT=0
TUNNEL_ACTIVE=0
TUNNEL_URL=""

# ═══════════════════════════════════════════════════
# BANNER
# ═══════════════════════════════════════════════════
banner() {
    clear
    echo -e "${CYAN}═══════════════════════════════════════════════════${NC}"
    echo -e "${WHITE}${BOLD}    HOTSPOT MANAGER v10.0 COMPLETE${NC}"
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
# INSTALL DEPENDENCIES
# ═══════════════════════════════════════════════════
install_deps() {
    echo -e "${YELLOW}[*] Checking packages...${NC}"
    
    pkg update -y &>/dev/null
    
    for pkg in iproute2 net-tools bc iptables ncurses-utils curl wget openssh nodejs-lts python; do
        if ! dpkg -s "$pkg" &>/dev/null; then
            echo -e "${YELLOW}Installing $pkg...${NC}"
            pkg install -y "$pkg" &>/dev/null
        fi
    done
    
    echo -e "${GREEN}[✓] Dependencies ready${NC}"
}

# ═══════════════════════════════════════════════════
# DETECT INTERFACE
# ═══════════════════════════════════════════════════
detect_interface() {
    [ $ROOT -eq 0 ] && return
    
    for iface in ap0 swlan0 wlan0 wlan1 rmnet_data0 rmnet_data1 rmnet_data2 rndis0; do
        local ip=$(su -c "ip addr show $iface 2>/dev/null | grep 'inet ' | grep -v '127.0.0.1' | awk '{print \$2}' | cut -d/ -f1")
        if [ -n "$ip" ]; then
            INTERFACE="$iface"
            LOCAL_IP="$ip"
            return
        fi
    done
}

# ═══════════════════════════════════════════════════
# CHECK CGNAT
# ═══════════════════════════════════════════════════
check_cgnat() {
    echo -e "${YELLOW}[*] Checking network type...${NC}"
    
    PUBLIC_IP=$(curl -s --connect-timeout 3 ifconfig.me || \
                curl -s --connect-timeout 3 icanhazip.com || \
                curl -s --connect-timeout 3 ipinfo.io/ip || \
                echo "Unknown")
    
    if [ "$PUBLIC_IP" != "Unknown" ]; then
        echo -e "${GREEN}[✓] Public IP: $PUBLIC_IP${NC}"
        
        # Check if behind CGNAT
        if [[ "$PUBLIC_IP" =~ ^100\.(6[4-9]|[7-9][0-9]|1[0-2][0-9])\. ]] || \
           [[ "$PUBLIC_IP" =~ ^10\. ]] || \
           [[ "$PUBLIC_IP" =~ ^172\.(1[6-9]|2[0-9]|3[0-1])\. ]] || \
           [[ "$PUBLIC_IP" =~ ^192\.168\. ]]; then
            BEHIND_CGNAT=1
            echo -e "${YELLOW}[!] Behind CGNAT (Use tunneling for public access)${NC}"
        fi
    fi
}

# ═══════════════════════════════════════════════════
# INIT CONFIG
# ═══════════════════════════════════════════════════
init_config() {
    mkdir -p "$CONFIG_DIR"
    touch "$CLIENTS_DB" "$BLOCKED_DB" "$PORTS_DB" "$TUNNEL_CONFIG"
}

# ═══════════════════════════════════════════════════
# GET CLIENTS
# ═══════════════════════════════════════════════════
get_clients() {
    [ $ROOT -eq 0 ] && return
    
    detect_interface
    su -c "cat /proc/net/arp 2>/dev/null" | grep "$INTERFACE" | grep -v "00:00:00:00:00:00" | awk '{print $1}'
}

# ═══════════════════════════════════════════════════
# SHOW CLIENTS
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
    echo -e "${GREEN}Local IP: $LOCAL_IP${NC}"
    echo -e "${GREEN}Public IP: $PUBLIC_IP${NC}"
    
    # Check for active tunnel
    if [ -f "$TUNNEL_CONFIG" ]; then
        TUNNEL_URL=$(cat "$TUNNEL_CONFIG" 2>/dev/null)
        [ -n "$TUNNEL_URL" ] && echo -e "${GREEN}Tunnel: ${CYAN}$TUNNEL_URL${NC}"
    fi
    
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
        
        tput cup 11 0
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
# BLOCK CLIENT
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

# ═══════════════════════════════════════════════════
# KICK CLIENT
# ═══════════════════════════════════════════════════
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
# MINECRAFT SERVER - QUICK SETUP
# ═══════════════════════════════════════════════════
minecraft_quick() {
    banner
    echo -e "${CYAN}═══════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}${BOLD}    MINECRAFT SERVER - QUICK SETUP${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════${NC}\n"
    
    echo -e "${YELLOW}Where are your friends?${NC}\n"
    
    echo -e "${CYAN}1.${NC} Same room/house ${GREEN}(0ms ping)${NC}"
    echo -e "${CYAN}2.${NC} Indonesia only ${GREEN}(15-30ms ping)${NC}"
    echo -e "${CYAN}3.${NC} International ${YELLOW}(50ms+ ping)${NC}"
    echo -e "${CYAN}0.${NC} Back"
    
    read -p $'\n'"Choose: " opt
    
    case $opt in
        1)
            # Local WiFi/Hotspot
            detect_interface
            
            echo -e "\n${GREEN}════════════════════════════════════════════════${NC}"
            echo -e "${GREEN}         LOCAL MINECRAFT SERVER${NC}"
            echo -e "${GREEN}════════════════════════════════════════════════${NC}\n"
            
            echo -e "${WHITE}Option 1: WiFi Hotspot${NC}"
            echo -e "1. Enable hotspot on your phone"
            echo -e "2. Friends connect to your hotspot"
            echo -e "3. Share this IP: ${CYAN}$LOCAL_IP:25565${NC}\n"
            
            echo -e "${WHITE}Option 2: Same WiFi${NC}"
            echo -e "1. All connect to same WiFi"
            echo -e "2. Share this IP: ${CYAN}$LOCAL_IP:25565${NC}\n"
            
            echo -e "${GREEN}Ping: 0ms (Perfect!)${NC}"
            ;;
            
        2)
            # Indonesia - Playit.gg
            echo -e "\n${YELLOW}Setting up for Indonesian players...${NC}"
            
            if [ ! -f "$HOME/playit" ]; then
                echo -e "${YELLOW}[*] Downloading playit.gg...${NC}"
                
                local arch=$(uname -m)
                case $arch in
                    aarch64|arm64)
                        wget -O $HOME/playit "https://playit.gg/downloads/playit-linux-aarch64" -q --show-progress
                        ;;
                    armv7l|arm)
                        wget -O $HOME/playit "https://playit.gg/downloads/playit-linux-arm7" -q --show-progress
                        ;;
                esac
                
                chmod +x $HOME/playit
            fi
            
            echo -e "\n${YELLOW}Starting Playit.gg...${NC}"
            pkill -f playit 2>/dev/null
            
            $HOME/playit &
            
            sleep 3
            
            echo -e "\n${GREEN}════════════════════════════════════════════════${NC}"
            echo -e "${GREEN}    PLAYIT.GG STARTED (SINGAPORE SERVER)${NC}"
            echo -e "${GREEN}════════════════════════════════════════════════${NC}\n"
            
            echo -e "${YELLOW}Steps:${NC}"
            echo -e "1. Check the link shown above"
            echo -e "2. Login with Google/Discord (FREE)"
            echo -e "3. Choose ${CYAN}Singapore${NC} region"
            echo -e "4. Get your address and share with friends!\n"
            
            echo -e "${GREEN}Expected ping: 15-30ms from Indonesia!${NC}"
            
            # Save to tunnel config
            echo "Playit.gg Active" > "$TUNNEL_CONFIG"
            ;;
            
        3)
            # International - ngrok
            echo -e "\n${YELLOW}Setting up for international players...${NC}"
            
            if [ ! -f "$HOME/ngrok" ]; then
                echo -e "${YELLOW}[*] Installing ngrok...${NC}"
                
                local arch=$(uname -m)
                case $arch in
                    aarch64|arm64)
                        wget -O ngrok.tgz "https://bin.equinox.io/c/bNyj1mQVY4c/ngrok-v3-stable-linux-arm64.tgz" -q --show-progress
                        ;;
                    armv7l|arm)
                        wget -O ngrok.tgz "https://bin.equinox.io/c/bNyj1mQVY4c/ngrok-v3-stable-linux-arm.tgz" -q --show-progress
                        ;;
                esac
                
                tar -xzf ngrok.tgz -C $HOME
                rm ngrok.tgz
                chmod +x $HOME/ngrok
            fi
            
            if ! grep -q "authtoken:" $HOME/.ngrok2/ngrok.yml 2>/dev/null; then
                echo -e "\n${YELLOW}Need ngrok account (FREE):${NC}"
                echo -e "1. Visit: ${CYAN}https://ngrok.com${NC}"
                echo -e "2. Sign up"
                echo -e "3. Get authtoken"
                read -p "Enter authtoken: " authtoken
                
                if [ -n "$authtoken" ]; then
                    $HOME/ngrok config add-authtoken "$authtoken"
                fi
            fi
            
            echo -e "\n${YELLOW}Starting ngrok (Singapore)...${NC}"
            pkill -f ngrok 2>/dev/null
            
            nohup $HOME/ngrok tcp 25565 --region ap > /tmp/ngrok.log 2>&1 &
            
            sleep 4
            
            local url=$(curl -s http://localhost:4040/api/tunnels 2>/dev/null | grep -o '"public_url":"[^"]*' | cut -d'"' -f4 | grep tcp)
            
            if [ -n "$url" ]; then
                echo "$url" > "$TUNNEL_CONFIG"
                
                echo -e "\n${GREEN}════════════════════════════════════════════════${NC}"
                echo -e "${GREEN}      MINECRAFT SERVER PUBLIC!${NC}"
                echo -e "${GREEN}════════════════════════════════════════════════${NC}\n"
                
                echo -e "${WHITE}Share this address:${NC}"
                echo -e "${CYAN}${BOLD}$url${NC}\n"
                
                echo -e "${YELLOW}Region: Singapore (50ms from Indonesia)${NC}"
            fi
            ;;
    esac
    
    read -p $'\n'"Press Enter..."
}

# ═══════════════════════════════════════════════════
# TUNNELING MENU
# ═══════════════════════════════════════════════════
tunnel_menu() {
    while true; do
        banner
        echo -e "${CYAN}═══════════════════════════════════════════════════${NC}"
        echo -e "${CYAN}${BOLD}       TUNNELING & PORT FORWARD${NC}"
        echo -e "${CYAN}═══════════════════════════════════════════════════${NC}\n"
        
        if [ $BEHIND_CGNAT -eq 1 ]; then
            echo -e "${YELLOW}[!] You are behind CGNAT${NC}"
            echo -e "${YELLOW}[!] Use tunneling for public access${NC}\n"
        fi
        
        # Check active tunnels
        local tunnel_status="${RED}None${NC}"
        if [ -f "$TUNNEL_CONFIG" ]; then
            local tunnel_info=$(cat "$TUNNEL_CONFIG" 2>/dev/null)
            [ -n "$tunnel_info" ] && tunnel_status="${GREEN}Active: $tunnel_info${NC}"
        fi
        
        echo -e "${YELLOW}Tunnel Status: $tunnel_status${NC}\n"
        
        echo -e "${CYAN}════════ Quick Setup ════════${NC}"
        echo -e "${CYAN}1.${NC} Minecraft Server (Auto best)"
        echo -e "${CYAN}2.${NC} Web Server"
        
        echo -e "\n${CYAN}════════ Indonesia Optimized ════════${NC}"
        echo -e "${CYAN}3.${NC} Playit.gg ${GREEN}(15-30ms)${NC}"
        echo -e "${CYAN}4.${NC} ngrok Asia ${GREEN}(20-50ms)${NC}"
        echo -e "${CYAN}5.${NC} Cloudflare Jakarta ${GREEN}(5-20ms)${NC}"
        
        echo -e "\n${CYAN}════════ Management ════════${NC}"
        echo -e "${CYAN}6.${NC} Stop all tunnels"
        echo -e "${CYAN}7.${NC} Test connection"
        echo -e "${CYAN}0.${NC} Back"
        
        echo -e "${CYAN}═══════════════════════════════════════════════════${NC}"
        
        read -p $'\n'"Choose: " opt
        
        case $opt in
            1) minecraft_quick ;;
            2)
                read -p "Web server port (8080): " port
                [ -z "$port" ] && port="8080"
                
                echo -e "\n${YELLOW}Starting web tunnel...${NC}"
                
                if command -v cloudflared &>/dev/null; then
                    pkill -f cloudflared 2>/dev/null
                    cloudflared tunnel --url http://localhost:$port 2>&1 | tee /tmp/cf.log &
                    
                    sleep 5
                    local cf_url=$(grep -o 'https://.*\.trycloudflare.com' /tmp/cf.log | head -1)
                    
                    if [ -n "$cf_url" ]; then
                        echo "$cf_url" > "$TUNNEL_CONFIG"
                        echo -e "\n${GREEN}Web server accessible at:${NC}"
                        echo -e "${CYAN}$cf_url${NC}"
                    fi
                else
                    echo -e "${RED}Install cloudflared first${NC}"
                fi
                
                read -p "Press Enter..."
                ;;
            3)
                # Playit.gg setup
                if [ ! -f "$HOME/playit" ]; then
                    echo -e "${YELLOW}Downloading playit.gg...${NC}"
                    local arch=$(uname -m)
                    case $arch in
                        aarch64|arm64)
                            wget -O $HOME/playit "https://playit.gg/downloads/playit-linux-aarch64" -q --show-progress
                            ;;
                        armv7l|arm)
                            wget -O $HOME/playit "https://playit.gg/downloads/playit-linux-arm7" -q --show-progress
                            ;;
                    esac
                    chmod +x $HOME/playit
                fi
                
                pkill -f playit 2>/dev/null
                $HOME/playit &
                
                echo -e "\n${GREEN}Playit.gg started!${NC}"
                echo -e "${YELLOW}Login and choose Singapore region${NC}"
                echo "Playit.gg Active" > "$TUNNEL_CONFIG"
                
                read -p "Press Enter..."
                ;;
            4)
                # ngrok Asia setup
                if [ ! -f "$HOME/ngrok" ]; then
                    echo -e "${YELLOW}Installing ngrok...${NC}"
                    local arch=$(uname -m)
                    case $arch in
                        aarch64|arm64)
                            wget -O ngrok.tgz "https://bin.equinox.io/c/bNyj1mQVY4c/ngrok-v3-stable-linux-arm64.tgz" -q --show-progress
                            ;;
                        armv7l|arm)
                            wget -O ngrok.tgz "https://bin.equinox.io/c/bNyj1mQVY4c/ngrok-v3-stable-linux-arm.tgz" -q --show-progress
                            ;;
                    esac
                    tar -xzf ngrok.tgz -C $HOME
                    rm ngrok.tgz
                    chmod +x $HOME/ngrok
                fi
                
                read -p "Port to forward: " port
                pkill -f ngrok 2>/dev/null
                
                nohup $HOME/ngrok tcp $port --region ap > /tmp/ngrok.log 2>&1 &
                
                sleep 4
                local url=$(curl -s http://localhost:4040/api/tunnels 2>/dev/null | grep -o '"public_url":"[^"]*' | cut -d'"' -f4 | head -1)
                
                if [ -n "$url" ]; then
                    echo "$url" > "$TUNNEL_CONFIG"
                    echo -e "\n${GREEN}ngrok tunnel active:${NC}"
                    echo -e "${CYAN}$url${NC}"
                fi
                
                read -p "Press Enter..."
                ;;
            5)
                # Cloudflare setup
                if ! command -v cloudflared &>/dev/null; then
                    echo -e "${YELLOW}Installing cloudflared...${NC}"
                    local arch=$(uname -m)
                    case $arch in
                        aarch64|arm64)
                            wget -O cloudflared https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-arm64
                            ;;
                        armv7l|arm)
                            wget -O cloudflared https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-arm
                            ;;
                    esac
                    chmod +x cloudflared
                    mv cloudflared $PREFIX/bin/
                fi
                
                read -p "Port to tunnel: " port
                pkill -f cloudflared 2>/dev/null
                
                cloudflared tunnel --url tcp://localhost:$port 2>&1 | tee /tmp/cf.log &
                
                sleep 5
                local cf_url=$(grep -o 'https://.*\.trycloudflare.com' /tmp/cf.log | head -1)
                
                if [ -n "$cf_url" ]; then
                    echo "$cf_url" > "$TUNNEL_CONFIG"
                    echo -e "\n${GREEN}Cloudflare tunnel (Jakarta):${NC}"
                    echo -e "${CYAN}$cf_url${NC}"
                fi
                
                read -p "Press Enter..."
                ;;
            6)
                echo -e "${YELLOW}Stopping all tunnels...${NC}"
                pkill -f "ngrok|playit|cloudflared|localtunnel" 2>/dev/null
                rm -f "$TUNNEL_CONFIG"
                echo -e "${GREEN}[✓] All tunnels stopped${NC}"
                read -p "Press Enter..."
                ;;
            7)
                echo -e "\n${YELLOW}Testing connections...${NC}\n"
                
                echo -e "${CYAN}Local Network:${NC}"
                ping -c 2 $LOCAL_IP 2>/dev/null && echo -e "${GREEN}[✓] Local OK${NC}" || echo -e "${RED}[✗] Local Failed${NC}"
                
                echo -e "\n${CYAN}Internet:${NC}"
                ping -c 2 google.com 2>/dev/null && echo -e "${GREEN}[✓] Internet OK${NC}" || echo -e "${RED}[✗] No Internet${NC}"
                
                echo -e "\n${CYAN}Port 25565:${NC}"
                timeout 1 nc -zv localhost 25565 &>/dev/null && echo -e "${GREEN}[✓] Minecraft port open${NC}" || echo -e "${YELLOW}[!] Port 25565 closed${NC}"
                
                read -p $'\n'"Press Enter..."
                ;;
            0) break ;;
        esac
    done
}

# ═══════════════════════════════════════════════════
# DEVICE MANAGEMENT MENU
# ═══════════════════════════════════════════════════
device_menu() {
    while true; do
        banner
        echo -e "${CYAN}═══════════════════════════════════════════════════${NC}"
        echo -e "${CYAN}${BOLD}         DEVICE MANAGEMENT${NC}"
        echo -e "${CYAN}═══════════════════════════════════════════════════${NC}\n"
        
        [ $ROOT -eq 1 ] && show_clients
        
        echo -e "\n${CYAN}═══════════════════════════════════════════════════${NC}"
        echo -e "${CYAN}1.${NC} Speed Control"
        echo -e "${CYAN}2.${NC} Block Device"
        echo -e "${CYAN}3.${NC} Unblock Device"
        echo -e "${CYAN}4.${NC} Kick Device"
        echo -e "${CYAN}5.${NC} Real-time Monitor"
        echo -e "${CYAN}0.${NC} Back"
        echo -e "${CYAN}═══════════════════════════════════════════════════${NC}"
        
        read -p $'\n'"Choose: " opt
        
        case $opt in
            1) set_speed ;;
            2) block_client ;;
            3) unblock_client ;;
            4) kick_client ;;
            5) monitor_stats ;;
            0) break ;;
        esac
    done
}

# ═══════════════════════════════════════════════════
# MAIN MENU
# ═══════════════════════════════════════════════════
main_menu() {
    while true; do
        banner
        detect_interface
        
        echo -e "${CYAN}═══════════════════════════════════════════════════${NC}"
        echo -e "${CYAN}${BOLD}             SYSTEM STATUS${NC}"
        echo -e "${CYAN}═══════════════════════════════════════════════════${NC}\n"
        
        echo -e "${YELLOW}Root:${NC}       $([ $ROOT -eq 1 ] && echo -e "${GREEN}YES${NC}" || echo -e "${RED}NO${NC}")"
        echo -e "${YELLOW}Interface:${NC}  ${GREEN}$INTERFACE${NC}"
        echo -e "${YELLOW}Local IP:${NC}   ${GREEN}${LOCAL_IP:-Not detected}${NC}"
        echo -e "${YELLOW}Public IP:${NC}  ${GREEN}${PUBLIC_IP:-Checking...}${NC}"
        echo -e "${YELLOW}CGNAT:${NC}      $([ $BEHIND_CGNAT -eq 1 ] && echo -e "${RED}YES${NC}" || echo -e "${GREEN}NO${NC}")"
        
        # Check tunnel status
        if [ -f "$TUNNEL_CONFIG" ]; then
            local tunnel_info=$(cat "$TUNNEL_CONFIG" 2>/dev/null | head -1)
            [ -n "$tunnel_info" ] && echo -e "${YELLOW}Tunnel:${NC}     ${GREEN}Active${NC}"
        fi
        
        echo -e "${YELLOW}Network:${NC}    $(network_stats)"
        
        echo -e "\n${CYAN}═══════════════════════════════════════════════════${NC}"
        echo -e "${CYAN}${BOLD}            MAIN MENU${NC}"
        echo -e "${CYAN}═══════════════════════════════════════════════════${NC}\n"
        
        echo -e "${CYAN}1.${NC} ${BOLD}Quick Minecraft Server${NC}"
        echo -e "${CYAN}2.${NC} Device Management"
        echo -e "${CYAN}3.${NC} Tunneling & Port Forward"
        echo -e "${CYAN}4.${NC} Real-time Monitor"
        echo -e "${CYAN}5.${NC} About"
        echo -e "${CYAN}0.${NC} Exit"
        
        echo -e "\n${CYAN}═══════════════════════════════════════════════════${NC}"
        
        read -p $'\n'"Choose: " opt
        
        case $opt in
            1) minecraft_quick ;;
            2) device_menu ;;
            3) tunnel_menu ;;
            4) monitor_stats ;;
            5)
                banner
                echo -e "${CYAN}═══════════════════════════════════════════════════${NC}"
                echo -e "${CYAN}${BOLD}                ABOUT${NC}"
                echo -e "${CYAN}═══════════════════════════════════════════════════${NC}\n"
                
                echo -e "${WHITE}${BOLD}Hotspot Manager v10.0 Complete${NC}"
                echo -e "${YELLOW}All-in-One Network Management${NC}\n"
                
                echo -e "${CYAN}Features:${NC}"
                echo -e "${GREEN}✓${NC} Hotspot device management"
                echo -e "${GREEN}✓${NC} Speed control per device"
                echo -e "${GREEN}✓${NC} Minecraft server hosting"
                echo -e "${GREEN}✓${NC} CGNAT bypass (tunneling)"
                echo -e "${GREEN}✓${NC} Indonesia optimized (low ping)"
                echo -e "${GREEN}✓${NC} Real-time monitoring"
                
                echo -e "\n${PURPLE}═══════════════════════════════════════════════════${NC}"
                echo -e "${PURPLE}${BOLD}         By: senzore ganteng${NC}"
                echo -e "${PURPLE}═══════════════════════════════════════════════════${NC}\n"
                
                read -p "Press Enter..."
                ;;
            0)
                echo -e "\n${PURPLE}By: senzore ganteng${NC}\n"
                exit 0
                ;;
        esac
    done
}

# ═══════════════════════════════════════════════════
# MAIN EXECUTION
# ═══════════════════════════════════════════════════
main() {
    [ "$1" = "--clean" ] || [ "$1" = "-c" ] && rm -rf "$CONFIG_DIR"
    
    banner
    echo -e "${CYAN}Starting Complete Edition...${NC}\n"
    
    check_root
    install_deps
    init_config
    check_cgnat
    
    echo -e "\n${GREEN}[✓] Ready${NC}"
    
    if [ $BEHIND_CGNAT -eq 1 ]; then
        echo -e "${YELLOW}[!] CGNAT detected - Use tunneling for public servers${NC}"
    fi
    
    read -p "Press Enter to continue..."
    
    main_menu
}

# RUN
main "$@"
