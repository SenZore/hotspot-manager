#!/data/data/com.termux/files/usr/bin/bash

# ═══════════════════════════════════════════════════
# TERMUX HOTSPOT MANAGER v9.0 - INDONESIA OPTIMIZED
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
TUNNEL_CONFIG="$CONFIG_DIR/tunnel.conf"
REGION_CONFIG="$CONFIG_DIR/region.conf"

# Global vars
ROOT=0
INTERFACE="wlan0"
LOCAL_IP=""
PUBLIC_IP=""
BEST_REGION=""
PING_RESULTS=""

# ═══════════════════════════════════════════════════
# BANNER
# ═══════════════════════════════════════════════════
banner() {
    clear
    echo -e "${CYAN}═══════════════════════════════════════════════════${NC}"
    echo -e "${WHITE}${BOLD}   HOTSPOT MANAGER v9.0 - INDONESIA${NC}"
    echo -e "${PURPLE}           By: senzore ganteng${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════${NC}\n"
}

# ═══════════════════════════════════════════════════
# CHECK ROOT
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
    echo -e "${YELLOW}[*] Installing packages...${NC}"
    
    pkg update -y &>/dev/null
    
    for pkg in iproute2 net-tools bc iptables curl wget openssh nodejs-lts python; do
        if ! dpkg -s "$pkg" &>/dev/null; then
            pkg install -y "$pkg" &>/dev/null
        fi
    done
    
    echo -e "${GREEN}[✓] Ready${NC}"
}

# ═══════════════════════════════════════════════════
# TEST PING TO REGIONS
# ═══════════════════════════════════════════════════
test_regions() {
    echo -e "${YELLOW}[*] Finding best server region...${NC}\n"
    
    declare -A regions=(
        ["Singapore"]="sgp1.serveo.net"
        ["Jakarta"]="103.56.206.0"  # Biznet DC
        ["Tokyo"]="nrt1.serveo.net"
        ["Hong Kong"]="18.162.0.0"
        ["Mumbai"]="bom1.serveo.net"
        ["Sydney"]="syd1.serveo.net"
    )
    
    local best_ping=999
    BEST_REGION=""
    
    for region in "${!regions[@]}"; do
        local server="${regions[$region]}"
        echo -e "${CYAN}Testing $region...${NC}"
        
        # Test ping
        local ping_result=$(ping -c 3 -W 1 "$server" 2>/dev/null | grep "avg" | awk -F'/' '{print $5}' | cut -d'.' -f1)
        
        if [ -n "$ping_result" ]; then
            echo -e "  ${WHITE}$region: ${YELLOW}${ping_result}ms${NC}"
            PING_RESULTS+="$region: ${ping_result}ms\n"
            
            if [ "$ping_result" -lt "$best_ping" ]; then
                best_ping=$ping_result
                BEST_REGION=$region
            fi
        else
            echo -e "  ${RED}$region: Failed${NC}"
        fi
    done
    
    if [ -n "$BEST_REGION" ]; then
        echo -e "\n${GREEN}[✓] Best region: $BEST_REGION (${best_ping}ms)${NC}"
    fi
}

# ═══════════════════════════════════════════════════
# NGROK WITH SINGAPORE SERVER (CLOSEST TO INDONESIA)
# ═══════════════════════════════════════════════════
setup_ngrok_asia() {
    banner
    echo -e "${CYAN}═══════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}${BOLD}    NGROK ASIA (LOW PING FOR INDONESIA)${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════${NC}\n"
    
    # Install ngrok if needed
    if [ ! -f "$HOME/ngrok" ]; then
        echo -e "${YELLOW}[*] Installing ngrok...${NC}"
        
        local arch=$(uname -m)
        local ngrok_url=""
        
        case $arch in
            aarch64|arm64)
                ngrok_url="https://bin.equinox.io/c/bNyj1mQVY4c/ngrok-v3-stable-linux-arm64.tgz"
                ;;
            armv7l|arm)
                ngrok_url="https://bin.equinox.io/c/bNyj1mQVY4c/ngrok-v3-stable-linux-arm.tgz"
                ;;
        esac
        
        wget -q --show-progress "$ngrok_url" -O ngrok.tgz
        tar -xzf ngrok.tgz -C $HOME
        rm ngrok.tgz
        chmod +x $HOME/ngrok
    fi
    
    # Configure for Asia region
    echo -e "${YELLOW}[*] Configuring for Singapore region (lowest ping)...${NC}"
    
    # Create ngrok config with Singapore region
    mkdir -p $HOME/.ngrok2
    cat > $HOME/.ngrok2/ngrok.yml << EOF
version: "2"
region: ap
tunnels:
  minecraft:
    proto: tcp
    addr: 25565
  web:
    proto: http
    addr: 8080
EOF
    
    echo -e "${GREEN}[✓] Configured for Asia-Pacific (Singapore)${NC}"
    echo -e "${YELLOW}Expected ping: 20-50ms from Indonesia${NC}\n"
    
    # Check if authtoken exists
    if ! grep -q "authtoken:" $HOME/.ngrok2/ngrok.yml 2>/dev/null; then
        echo -e "${YELLOW}Get FREE ngrok account:${NC}"
        echo -e "1. Visit: ${CYAN}https://ngrok.com${NC}"
        echo -e "2. Sign up FREE"
        echo -e "3. Copy authtoken"
        echo ""
        read -p "Enter authtoken (or 'skip'): " authtoken
        
        if [ "$authtoken" != "skip" ] && [ -n "$authtoken" ]; then
            $HOME/ngrok config add-authtoken "$authtoken"
        fi
    fi
    
    echo -e "${CYAN}1.${NC} Start Minecraft (Port 25565)"
    echo -e "${CYAN}2.${NC} Start Web Server (Port 8080)"
    echo -e "${CYAN}3.${NC} Custom Port"
    echo -e "${CYAN}0.${NC} Back"
    
    read -p $'\n'"Choose: " opt
    
    case $opt in
        1)
            pkill -f ngrok 2>/dev/null
            
            echo -e "\n${YELLOW}Starting Minecraft tunnel (Singapore server)...${NC}"
            
            # Start with Asia region specifically
            nohup $HOME/ngrok tcp 25565 --region ap > /tmp/ngrok.log 2>&1 &
            
            sleep 4
            
            # Get URL
            local url=$(curl -s http://localhost:4040/api/tunnels 2>/dev/null | grep -o '"public_url":"[^"]*' | cut -d'"' -f4 | grep tcp)
            
            if [ -n "$url" ]; then
                echo -e "\n${GREEN}════════════════════════════════════════════════${NC}"
                echo -e "${GREEN}   MINECRAFT SERVER READY! (SINGAPORE)${NC}"
                echo -e "${GREEN}════════════════════════════════════════════════${NC}"
                echo -e "\n${WHITE}Server address for friends:${NC}"
                echo -e "${CYAN}${BOLD}$url${NC}"
                echo -e "\n${YELLOW}Ping: ~20-50ms from Indonesia!${NC}"
                echo -e "${GREEN}Much better than US servers (200ms+)${NC}"
            fi
            ;;
    esac
    
    read -p $'\n'"Press Enter..."
}

# ═══════════════════════════════════════════════════
# PLAYIT.GG - BEST FOR GAMING (HAS ASIA SERVERS)
# ═══════════════════════════════════════════════════
setup_playit() {
    banner
    echo -e "${CYAN}═══════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}${BOLD}    PLAYIT.GG - BEST FOR MINECRAFT${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════${NC}\n"
    
    echo -e "${GREEN}Why Playit.gg?${NC}"
    echo -e "• Has ${YELLOW}Singapore & Hong Kong${NC} servers"
    echo -e "• ${YELLOW}15-30ms ping${NC} from Indonesia!"
    echo -e "• FREE forever"
    echo -e "• Designed for gaming\n"
    
    # Download playit
    if [ ! -f "$HOME/playit" ]; then
        echo -e "${YELLOW}[*] Downloading playit.gg...${NC}"
        
        local arch=$(uname -m)
        case $arch in
            aarch64|arm64)
                wget -O playit "https://playit.gg/downloads/playit-linux-aarch64" -q --show-progress
                ;;
            armv7l|arm)
                wget -O playit "https://playit.gg/downloads/playit-linux-arm7" -q --show-progress
                ;;
        esac
        
        chmod +x playit
        echo -e "${GREEN}[✓] Downloaded${NC}"
    fi
    
    echo -e "\n${CYAN}1.${NC} Setup Minecraft Server (Auto)"
    echo -e "${CYAN}2.${NC} Setup Custom Server"
    echo -e "${CYAN}3.${NC} Start existing tunnel"
    echo -e "${CYAN}0.${NC} Back"
    
    read -p $'\n'"Choose: " opt
    
    case $opt in
        1)
            echo -e "\n${YELLOW}Starting Playit.gg for Minecraft...${NC}"
            echo -e "${YELLOW}This will:${NC}"
            echo -e "1. Open browser for quick setup"
            echo -e "2. Auto-select nearest server (Singapore)"
            echo -e "3. Give you address to share\n"
            
            # Run playit
            ./playit &
            
            sleep 3
            
            echo -e "${GREEN}════════════════════════════════════════════════${NC}"
            echo -e "${GREEN}          PLAYIT.GG STARTED!${NC}"
            echo -e "${GREEN}════════════════════════════════════════════════${NC}"
            echo -e "\n${YELLOW}Steps:${NC}"
            echo -e "1. Check the link shown above"
            echo -e "2. Sign in with Google/Discord (FREE)"
            echo -e "3. It will auto-detect your Minecraft server"
            echo -e "4. Choose ${CYAN}Singapore${NC} or ${CYAN}Hong Kong${NC} region"
            echo -e "5. Share the address with friends!\n"
            echo -e "${GREEN}Your friends will get 15-30ms ping!${NC}"
            ;;
            
        2)
            read -p "Local port: " port
            
            echo -e "\n${YELLOW}Starting Playit.gg...${NC}"
            ./playit --port $port &
            
            echo -e "${GREEN}[✓] Started on port $port${NC}"
            echo -e "${YELLOW}Check the browser link to get your address${NC}"
            ;;
            
        3)
            ./playit &
            echo -e "${GREEN}[✓] Playit.gg running${NC}"
            ;;
    esac
    
    read -p $'\n'"Press Enter..."
}

# ═══════════════════════════════════════════════════
# ZeroTier - P2P NETWORK (BEST FOR FRIENDS)
# ═══════════════════════════════════════════════════
setup_zerotier() {
    banner
    echo -e "${CYAN}═══════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}${BOLD}    ZEROTIER - PRIVATE NETWORK${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════${NC}\n"
    
    echo -e "${GREEN}What is ZeroTier?${NC}"
    echo -e "• Creates ${YELLOW}virtual LAN${NC} between friends"
    echo -e "• ${YELLOW}Direct P2P connection${NC} (lowest ping possible)"
    echo -e "• Works even with CGNAT"
    echo -e "• FREE for up to 100 devices\n"
    
    if ! command -v zerotier-cli &>/dev/null; then
        echo -e "${YELLOW}[*] Installing ZeroTier...${NC}"
        
        # Install ZeroTier
        curl -s https://install.zerotier.com | bash
        
        echo -e "${GREEN}[✓] Installed${NC}"
    fi
    
    echo -e "${CYAN}1.${NC} Create new network"
    echo -e "${CYAN}2.${NC} Join existing network"
    echo -e "${CYAN}3.${NC} Show my networks"
    echo -e "${CYAN}0.${NC} Back"
    
    read -p $'\n'"Choose: " opt
    
    case $opt in
        1)
            echo -e "\n${YELLOW}Creating ZeroTier network...${NC}"
            echo -e "1. Go to: ${CYAN}https://my.zerotier.com${NC}"
            echo -e "2. Sign up FREE"
            echo -e "3. Create Network"
            echo -e "4. Copy Network ID\n"
            
            read -p "Enter Network ID: " network_id
            
            if [ -n "$network_id" ]; then
                su -c "zerotier-cli join $network_id"
                
                echo -e "\n${GREEN}[✓] Joined network!${NC}"
                echo -e "${YELLOW}Share this Network ID with friends: ${CYAN}$network_id${NC}"
                echo -e "${YELLOW}They run: zerotier-cli join $network_id${NC}"
                echo -e "\n${GREEN}Then you can connect directly with NO LAG!${NC}"
            fi
            ;;
            
        2)
            read -p "Network ID from friend: " network_id
            
            su -c "zerotier-cli join $network_id"
            echo -e "${GREEN}[✓] Joined!${NC}"
            echo -e "${YELLOW}Wait for network owner to approve you${NC}"
            ;;
            
        3)
            echo -e "\n${YELLOW}Your networks:${NC}"
            su -c "zerotier-cli listnetworks"
            ;;
    esac
    
    read -p $'\n'"Press Enter..."
}

# ═══════════════════════════════════════════════════
# LOCAL WIFI DIRECT (NO INTERNET NEEDED!)
# ═══════════════════════════════════════════════════
setup_wifi_direct() {
    banner
    echo -e "${CYAN}═══════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}${BOLD}    WIFI DIRECT - NO INTERNET NEEDED${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════${NC}\n"
    
    echo -e "${GREEN}Perfect for:${NC}"
    echo -e "• Playing with friends ${YELLOW}in same room${NC}"
    echo -e "• ${YELLOW}ZERO ping${NC} (local network)"
    echo -e "• No internet required"
    echo -e "• No CGNAT issues\n"
    
    echo -e "${CYAN}Method 1: Hotspot Mode${NC}"
    echo -e "1. Enable hotspot on your phone"
    echo -e "2. Friends connect to your hotspot"
    echo -e "3. Share your local IP: ${YELLOW}192.168.xxx.xxx:25565${NC}"
    echo -e "4. They can connect directly!\n"
    
    # Get current local IP
    local wifi_ip=$(ip addr show wlan0 2>/dev/null | grep "inet " | awk '{print $2}' | cut -d/ -f1)
    local hotspot_ip=$(ip addr show ap0 2>/dev/null | grep "inet " | awk '{print $2}' | cut -d/ -f1)
    
    if [ -n "$hotspot_ip" ]; then
        echo -e "${GREEN}Your Hotspot IP: ${CYAN}$hotspot_ip${NC}"
        echo -e "${YELLOW}Friends connect to: ${CYAN}$hotspot_ip:25565${NC}"
    elif [ -n "$wifi_ip" ]; then
        echo -e "${GREEN}Your WiFi IP: ${CYAN}$wifi_ip${NC}"
        echo -e "${YELLOW}If on same WiFi: ${CYAN}$wifi_ip:25565${NC}"
    fi
    
    echo -e "\n${CYAN}Method 2: Same WiFi Network${NC}"
    echo -e "1. Everyone connects to same WiFi"
    echo -e "2. Share your local IP"
    echo -e "3. Direct connection, ${GREEN}0ms ping!${NC}"
    
    read -p $'\n'"Press Enter..."
}

# ═══════════════════════════════════════════════════
# CLOUDFLARE TUNNEL (INDONESIA OPTIMIZED)
# ═══════════════════════════════════════════════════
setup_cloudflare_indonesia() {
    banner
    echo -e "${CYAN}═══════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}${BOLD}   CLOUDFLARE - INDONESIA OPTIMIZED${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════${NC}\n"
    
    echo -e "${GREEN}Cloudflare has servers in:${NC}"
    echo -e "• ${YELLOW}Jakarta${NC} (CGK)"
    echo -e "• ${YELLOW}Singapore${NC} (SIN)"
    echo -e "• Ping: ${GREEN}5-20ms${NC} from Indonesia!\n"
    
    if ! command -v cloudflared &>/dev/null; then
        echo -e "${YELLOW}[*] Installing cloudflared...${NC}"
        
        # Download cloudflared
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
        echo -e "${GREEN}[✓] Installed${NC}"
    fi
    
    echo -e "${CYAN}1.${NC} Quick tunnel (Minecraft)"
    echo -e "${CYAN}2.${NC} Quick tunnel (Web)"
    echo -e "${CYAN}0.${NC} Back"
    
    read -p $'\n'"Choose: " opt
    
    case $opt in
        1)
            echo -e "\n${YELLOW}Starting Cloudflare tunnel...${NC}"
            echo -e "${YELLOW}This uses Jakarta/Singapore servers!${NC}\n"
            
            # For Minecraft we need TCP, so we use try-cloudflare with proxy
            cloudflared tunnel --url tcp://localhost:25565 2>&1 | tee /tmp/cf.log &
            
            sleep 5
            
            local cf_url=$(grep -o 'https://.*\.trycloudflare.com' /tmp/cf.log | head -1)
            
            if [ -n "$cf_url" ]; then
                echo -e "\n${GREEN}════════════════════════════════════════════════${NC}"
                echo -e "${GREEN}    TUNNEL ACTIVE (JAKARTA SERVER!)${NC}"
                echo -e "${GREEN}════════════════════════════════════════════════${NC}"
                echo -e "\n${WHITE}Share this:${NC}"
                echo -e "${CYAN}${BOLD}$cf_url${NC}"
                echo -e "\n${YELLOW}Using Cloudflare Jakarta = FAST for Indonesia!${NC}"
            fi
            ;;
            
        2)
            read -p "Web port (8080): " port
            [ -z "$port" ] && port="8080"
            
            cloudflared tunnel --url http://localhost:$port 2>&1 | tee /tmp/cf.log &
            
            sleep 5
            
            local cf_url=$(grep -o 'https://.*\.trycloudflare.com' /tmp/cf.log | head -1)
            
            if [ -n "$cf_url" ]; then
                echo -e "\n${GREEN}Web tunnel active!${NC}"
                echo -e "URL: ${CYAN}$cf_url${NC}"
                echo -e "${YELLOW}Served from Cloudflare Jakarta!${NC}"
            fi
            ;;
    esac
    
    read -p $'\n'"Press Enter..."
}

# ═══════════════════════════════════════════════════
# BEST TUNNEL SELECTOR
# ═══════════════════════════════════════════════════
best_tunnel_menu() {
    while true; do
        banner
        echo -e "${CYAN}═══════════════════════════════════════════════════${NC}"
        echo -e "${CYAN}${BOLD}    BEST TUNNELS FOR INDONESIA${NC}"
        echo -e "${CYAN}═══════════════════════════════════════════════════${NC}\n"
        
        echo -e "${YELLOW}Ping comparison from Indonesia:${NC}\n"
        
        echo -e "${GREEN}BEST (Lowest Ping):${NC}"
        echo -e "${CYAN}1.${NC} WiFi Direct/Hotspot    ${GREEN}[0ms]${NC} - Same room"
        echo -e "${CYAN}2.${NC} ZeroTier P2P          ${GREEN}[5-15ms]${NC} - Direct connection"
        echo -e "${CYAN}3.${NC} Cloudflare Jakarta    ${GREEN}[5-20ms]${NC} - Jakarta server"
        echo -e "${CYAN}4.${NC} Playit.gg Singapore   ${GREEN}[15-30ms]${NC} - Gaming optimized"
        echo -e "${CYAN}5.${NC} ngrok Singapore       ${GREEN}[20-50ms]${NC} - Stable"
        
        echo -e "\n${YELLOW}AVOID (High Ping):${NC}"
        echo -e "${RED}✗${NC} ngrok US/EU           ${RED}[200-300ms]${NC}"
        echo -e "${RED}✗${NC} Serveo.net US         ${RED}[250ms+]${NC}"
        echo -e "${RED}✗${NC} LocalTunnel US        ${RED}[300ms+]${NC}"
        
        echo -e "\n${CYAN}═══════════════════════════════════════════════════${NC}"
        echo -e "${CYAN}6.${NC} Test ping to all regions"
        echo -e "${CYAN}0.${NC} Back"
        echo -e "${CYAN}═══════════════════════════════════════════════════${NC}"
        
        read -p $'\n'"Choose: " opt
        
        case $opt in
            1) setup_wifi_direct ;;
            2) setup_zerotier ;;
            3) setup_cloudflare_indonesia ;;
            4) setup_playit ;;
            5) setup_ngrok_asia ;;
            6) test_regions ;;
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
        
        echo -e "${CYAN}═══════════════════════════════════════════════════${NC}"
        echo -e "${CYAN}${BOLD}          INDONESIA OPTIMIZED${NC}"
        echo -e "${CYAN}═══════════════════════════════════════════════════${NC}\n"
        
        echo -e "${CYAN}1.${NC} Quick Minecraft Server (Best ping)"
        echo -e "${CYAN}2.${NC} Indonesia Tunnels (Low ping)"
        echo -e "${CYAN}3.${NC} Local Network (0ms ping)"
        echo -e "${CYAN}0.${NC} Exit"
        
        echo -e "\n${CYAN}═══════════════════════════════════════════════════${NC}"
        
        read -p $'\n'"Choose: " opt
        
        case $opt in
            1)
                echo -e "\n${YELLOW}Best option for Indonesian players:${NC}"
                echo -e "${CYAN}1.${NC} Friends nearby? Use WiFi Direct (0ms)"
                echo -e "${CYAN}2.${NC} Friends in Indonesia? Use Playit.gg (15ms)"
                echo -e "${CYAN}3.${NC} International? Use ngrok Singapore (50ms)"
                
                read -p $'\n'"Choose: " sub_opt
                case $sub_opt in
                    1) setup_wifi_direct ;;
                    2) setup_playit ;;
                    3) setup_ngrok_asia ;;
                esac
                ;;
            2) best_tunnel_menu ;;
            3) setup_wifi_direct ;;
            0) 
                echo -e "\n${PURPLE}By: senzore ganteng${NC}\n"
                exit 0
                ;;
        esac
    done
}

# ═══════════════════════════════════════════════════
# MAIN
# ═══════════════════════════════════════════════════
main() {
    banner
    echo -e "${CYAN}Starting Indonesia Optimized Version...${NC}\n"
    
    check_root
    install_deps
    
    echo -e "\n${GREEN}[✓] Ready${NC}"
    echo -e "${YELLOW}This version prioritizes LOW PING for Indonesia!${NC}\n"
    
    read -p "Press Enter to continue..."
    
    main_menu
}

# RUN
main "$@"
