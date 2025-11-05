#!/data/data/com.termux/files/usr/bin/bash

# ═══════════════════════════════════════════════════
# HOTSPOT MANAGER v14.0 - FIXED ROOT
# By: senzore ganteng
# ═══════════════════════════════════════════════════

# Colors
R='\033[0;31m'
G='\033[0;32m'
Y='\033[1;33m'
C='\033[0;36m'
N='\033[0m'

# Config
DIR="$HOME/.hotspot"
mkdir -p "$DIR"

# Global root status
HAS_ROOT=0

# ═══════════════════════════════════════════════════
# SIMPLE BANNER
# ═══════════════════════════════════════════════════
show() {
    clear
    echo -e "${C}═══════════════════════════════════════════════════${N}"
    echo -e "${C}         HOTSPOT MANAGER v14.0${N}"
    echo -e "${C}         By: senzore ganteng${N}"
    echo -e "${C}═══════════════════════════════════════════════════${N}\n"
}

# ═══════════════════════════════════════════════════
# ROOT CHECK - FIXED VERSION
# ═══════════════════════════════════════════════════
check_root() {
    echo -e "${Y}Checking root access...${N}"
    
    # Method 1: Simple su test
    if su -c "whoami" 2>/dev/null | grep -q "root"; then
        HAS_ROOT=1
        echo -e "${G}[✓] Root: GRANTED${N}"
        return 0
    fi
    
    # Method 2: Try with id
    if su -c "id" 2>/dev/null | grep -q "uid=0"; then
        HAS_ROOT=1
        echo -e "${G}[✓] Root: GRANTED${N}"
        return 0
    fi
    
    # Method 3: Try different su format
    if su 0 id 2>/dev/null | grep -q "uid=0"; then
        HAS_ROOT=1
        echo -e "${G}[✓] Root: GRANTED${N}"
        return 0
    fi
    
    # Method 4: Check if su exists and test write
    if command -v su &>/dev/null; then
        if su -c "test -w /system" 2>/dev/null; then
            HAS_ROOT=1
            echo -e "${G}[✓] Root: GRANTED${N}"
            return 0
        fi
    fi
    
    # No root found
    HAS_ROOT=0
    echo -e "${R}[✗] Root: NOT FOUND${N}"
    echo -e "${Y}Please grant root permission when prompted!${N}"
    echo -e "${Y}Trying to request root...${N}"
    
    # Try to trigger root prompt
    su -c "echo 'Root test'" 2>/dev/null
    
    # Check again after prompt
    if su -c "id" 2>/dev/null | grep -q "uid=0"; then
        HAS_ROOT=1
        echo -e "${G}[✓] Root: NOW GRANTED${N}"
        return 0
    fi
    
    echo -e "${R}This app requires root to work!${N}"
    echo -e "${Y}Install Magisk/KernelSU and try again${N}"
    exit 1
}

# ═══════════════════════════════════════════════════
# RUN AS ROOT - FIXED
# ═══════════════════════════════════════════════════
run() {
    if [ $HAS_ROOT -eq 1 ]; then
        su -c "$1" 2>/dev/null
    else
        echo -e "${R}No root!${N}"
        return 1
    fi
}

# ═══════════════════════════════════════════════════
# SET TTL
# ═══════════════════════════════════════════════════
fix_ttl() {
    echo -e "${Y}Setting TTL to 65...${N}"
    
    # Method 1: Direct echo
    run "echo 65 > /proc/sys/net/ipv4/ip_default_ttl"
    
    # Method 2: sysctl
    run "sysctl -w net.ipv4.ip_default_ttl=65"
    
    # Method 3: iptables TTL
    run "iptables -t mangle -F POSTROUTING 2>/dev/null"
    run "iptables -t mangle -A POSTROUTING -j TTL --ttl-set 65"
    
    # Enable IP forwarding
    run "echo 1 > /proc/sys/net/ipv4/ip_forward"
    run "sysctl -w net.ipv4.ip_forward=1"
    
    echo -e "${G}[✓] TTL set to 65${N}"
    echo -e "${G}[✓] IP Forward enabled${N}"
}

# ═══════════════════════════════════════════════════
# GET CLIENTS - MULTIPLE METHODS
# ═══════════════════════════════════════════════════
get_ips() {
    local all_ips=""
    
    # Method 1: ARP table
    local arp_ips=$(run "cat /proc/net/arp 2>/dev/null | grep -v IP | awk '{print \$1}' | grep -E '^192\.|^10\.|^172\.'")
    all_ips="$all_ips $arp_ips"
    
    # Method 2: ip neigh
    local neigh_ips=$(run "ip neigh 2>/dev/null | grep -v FAILED | awk '{print \$1}' | grep -E '^192\.|^10\.|^172\.'")
    all_ips="$all_ips $neigh_ips"
    
    # Method 3: arp command
    local arp_cmd=$(run "arp -n 2>/dev/null | grep -v incomplete | tail -n +2 | awk '{print \$1}' | grep -E '^192\.|^10\.|^172\.'")
    all_ips="$all_ips $arp_cmd"
    
    # Method 4: DHCP leases
    local dhcp_ips=$(run "cat /data/misc/dhcp/dnsmasq.leases 2>/dev/null | awk '{print \$3}'")
    all_ips="$all_ips $dhcp_ips"
    
    # Remove duplicates and sort
    echo "$all_ips" | tr ' ' '\n' | grep -E '^[0-9]+\.' | sort -u | grep -v '^$'
}

# ═══════════════════════════════════════════════════
# SHOW CLIENTS
# ═══════════════════════════════════════════════════
show_clients() {
    echo -e "${Y}Scanning for devices...${N}\n"
    
    local ips=$(get_ips)
    
    if [ -z "$ips" ]; then
        echo -e "${R}No devices found${N}"
        echo -e "${Y}Make sure:${N}"
        echo -e "1. Hotspot is ON"
        echo -e "2. Devices are connected"
        echo -e "3. You have root access"
        return 1
    fi
    
    local n=1
    echo "$ips" > "$DIR/clients.tmp"
    
    while read ip; do
        [ -z "$ip" ] && continue
        printf "${C}%2d.${N} %s\n" "$n" "$ip"
        ((n++))
    done <<< "$ips"
    
    echo -e "\n${G}Found $((n-1)) devices${N}"
    return 0
}

# ═══════════════════════════════════════════════════
# SPEED LIMIT - IPTABLES METHOD
# ═══════════════════════════════════════════════════
limit() {
    show
    echo -e "${C}══════ SPEED LIMIT ══════${N}\n"
    
    show_clients || { sleep 2; return; }
    
    echo -e "\n${Y}Options:${N}"
    echo -e "${G}0${N}  = Limit ALL devices"
    echo -e "${R}99${N} = Remove ALL limits"
    echo -e "${C}#${N}  = Select specific device"
    
    read -p $'\nYour choice: ' num
    
    # Remove all limits
    if [ "$num" = "99" ]; then
        echo -e "\n${Y}Removing all limits...${N}"
        
        # Clear iptables rules
        run "iptables -F FORWARD"
        run "iptables -t mangle -F"
        
        # Clear tc on common interfaces
        for iface in wlan0 ap0 swlan0 wlan1; do
            run "tc qdisc del dev $iface root 2>/dev/null"
        done
        
        echo -e "${G}[✓] All limits removed${N}"
        sleep 2
        return
    fi
    
    # Get target IPs
    local targets=""
    if [ "$num" = "0" ]; then
        targets=$(cat "$DIR/clients.tmp" 2>/dev/null)
        echo -e "\n${Y}Limiting ALL devices...${N}"
    else
        targets=$(sed -n "${num}p" "$DIR/clients.tmp" 2>/dev/null)
        if [ -z "$targets" ]; then
            echo -e "${R}Invalid selection${N}"
            sleep 2
            return
        fi
        echo -e "\n${Y}Limiting device: $targets${N}"
    fi
    
    # Apply 50KB/s limit using iptables
    while read ip; do
        [ -z "$ip" ] && continue
        
        echo -e "${Y}Setting limit for $ip...${N}"
        
        # Method 1: Using hashlimit (50KB/s)
        run "iptables -D FORWARD -s $ip -m hashlimit --hashlimit-name up_$ip --hashlimit-above 50kb/s --hashlimit-mode srcip -j DROP 2>/dev/null"
        run "iptables -D FORWARD -d $ip -m hashlimit --hashlimit-name down_$ip --hashlimit-above 50kb/s --hashlimit-mode dstip -j DROP 2>/dev/null"
        
        run "iptables -I FORWARD -s $ip -m hashlimit --hashlimit-name up_$ip --hashlimit-above 50kb/s --hashlimit-mode srcip -j DROP"
        run "iptables -I FORWARD -d $ip -m hashlimit --hashlimit-name down_$ip --hashlimit-above 50kb/s --hashlimit-mode dstip -j DROP"
        
        echo -e "${G}[✓] Limited: $ip (50KB/s)${N}"
    done <<< "$targets"
    
    sleep 2
}

# ═══════════════════════════════════════════════════
# BLOCK DEVICE
# ═══════════════════════════════════════════════════
block() {
    show
    echo -e "${C}══════ BLOCK DEVICE ══════${N}\n"
    
    show_clients || { sleep 2; return; }
    
    read -p $'\nBlock which device? ' num
    
    local ip=$(sed -n "${num}p" "$DIR/clients.tmp" 2>/dev/null)
    
    if [ -n "$ip" ]; then
        echo -e "\n${Y}Blocking $ip...${N}"
        
        # Block completely
        run "iptables -I INPUT -s $ip -j DROP"
        run "iptables -I FORWARD -s $ip -j DROP"
        run "iptables -I FORWARD -d $ip -j DROP"
        
        # Save to blocked list
        echo "$ip" >> "$DIR/blocked"
        
        echo -e "${G}[✓] Device blocked: $ip${N}"
    else
        echo -e "${R}Invalid selection${N}"
    fi
    
    sleep 2
}

# ═══════════════════════════════════════════════════
# UNBLOCK DEVICE
# ═══════════════════════════════════════════════════
unblock() {
    show
    echo -e "${C}══════ UNBLOCK DEVICE ══════${N}\n"
    
    if [ ! -s "$DIR/blocked" ]; then
        echo -e "${R}No blocked devices${N}"
        sleep 2
        return
    fi
    
    echo -e "${Y}Blocked devices:${N}\n"
    
    local n=1
    while read ip; do
        [ -z "$ip" ] && continue
        printf "${C}%2d.${N} %s\n" "$n" "$ip"
        ((n++))
    done < "$DIR/blocked"
    
    read -p $'\nUnblock which? ' num
    
    local ip=$(sed -n "${num}p" "$DIR/blocked" 2>/dev/null)
    
    if [ -n "$ip" ]; then
        echo -e "\n${Y}Unblocking $ip...${N}"
        
        # Remove block rules
        run "iptables -D INPUT -s $ip -j DROP 2>/dev/null"
        run "iptables -D FORWARD -s $ip -j DROP 2>/dev/null"
        run "iptables -D FORWARD -d $ip -j DROP 2>/dev/null"
        
        # Remove from blocked list
        grep -v "^$ip$" "$DIR/blocked" > "$DIR/blocked.tmp" 2>/dev/null
        mv "$DIR/blocked.tmp" "$DIR/blocked" 2>/dev/null
        
        echo -e "${G}[✓] Device unblocked: $ip${N}"
    else
        echo -e "${R}Invalid selection${N}"
    fi
    
    sleep 2
}

# ═══════════════════════════════════════════════════
# KICK DEVICE
# ═══════════════════════════════════════════════════
kick() {
    show
    echo -e "${C}══════ KICK DEVICE ══════${N}\n"
    
    show_clients || { sleep 2; return; }
    
    read -p $'\nKick which device? ' num
    
    local ip=$(sed -n "${num}p" "$DIR/clients.tmp" 2>/dev/null)
    
    if [ -n "$ip" ]; then
        echo -e "\n${Y}Kicking $ip...${N}"
        
        # Clear ARP entry
        run "arp -d $ip 2>/dev/null"
        
        # Remove from neighbor table on all interfaces
        for iface in wlan0 ap0 swlan0 wlan1; do
            run "ip neigh del $ip dev $iface 2>/dev/null"
        done
        
        # Temporarily block (5 seconds)
        run "iptables -I INPUT -s $ip -j DROP"
        run "iptables -I FORWARD -s $ip -j DROP"
        
        echo -e "${G}[✓] Device kicked${N}"
        echo -e "${Y}Blocking for 5 seconds...${N}"
        
        sleep 5
        
        # Remove temporary block
        run "iptables -D INPUT -s $ip -j DROP 2>/dev/null"
        run "iptables -D FORWARD -s $ip -j DROP 2>/dev/null"
        
        echo -e "${G}[✓] Device can reconnect now${N}"
    else
        echo -e "${R}Invalid selection${N}"
    fi
    
    sleep 2
}

# ═══════════════════════════════════════════════════
# RESET ALL
# ═══════════════════════════════════════════════════
reset_all() {
    show
    echo -e "${C}══════ RESET ALL ══════${N}\n"
    
    echo -e "${Y}Resetting everything...${N}\n"
    
    # Clear iptables
    echo "Clearing firewall rules..."
    run "iptables -F"
    run "iptables -t nat -F"
    run "iptables -t mangle -F"
    run "iptables -X"
    
    # Reset policies
    echo "Resetting policies..."
    run "iptables -P INPUT ACCEPT"
    run "iptables -P FORWARD ACCEPT"
    run "iptables -P OUTPUT ACCEPT"
    
    # Setup basic NAT for hotspot
    echo "Setting up NAT..."
    run "iptables -t nat -A POSTROUTING -j MASQUERADE"
    
    # Set TTL
    echo "Setting TTL to 65..."
    run "echo 65 > /proc/sys/net/ipv4/ip_default_ttl"
    run "iptables -t mangle -A POSTROUTING -j TTL --ttl-set 65"
    
    # Enable forwarding
    echo "Enabling forwarding..."
    run "echo 1 > /proc/sys/net/ipv4/ip_forward"
    
    # Clear bandwidth limits
    echo "Removing bandwidth limits..."
    for iface in wlan0 ap0 swlan0 wlan1; do
        run "tc qdisc del dev $iface root 2>/dev/null"
    done
    
    # Clear block list
    > "$DIR/blocked"
    
    echo -e "\n${G}[✓] Everything reset!${N}"
    echo -e "${G}• TTL: 65${N}"
    echo -e "${G}• Forwarding: ON${N}"
    echo -e "${G}• NAT: ON${N}"
    echo -e "${G}• Limits: OFF${N}"
    echo -e "${G}• Blocks: CLEARED${N}"
    
    sleep 3
}

# ═══════════════════════════════════════════════════
# STATUS INFO
# ═══════════════════════════════════════════════════
info() {
    show
    echo -e "${C}══════ STATUS INFO ══════${N}\n"
    
    echo -e "${Y}System Status:${N}"
    echo -e "Root: $([ $HAS_ROOT -eq 1 ] && echo -e "${G}YES${N}" || echo -e "${R}NO${N}")"
    echo -e "TTL: $(cat /proc/sys/net/ipv4/ip_default_ttl 2>/dev/null || echo 'Error')"
    echo -e "IP Forward: $(cat /proc/sys/net/ipv4/ip_forward 2>/dev/null || echo 'Error')"
    
    echo -e "\n${Y}Network:${N}"
    local count=$(get_ips | wc -l)
    echo -e "Connected devices: $count"
    
    if [ -s "$DIR/blocked" ]; then
        echo -e "\n${Y}Blocked devices:${N}"
        cat "$DIR/blocked"
    else
        echo -e "\n${Y}Blocked devices:${N} None"
    fi
    
    echo -e "\n${Y}Interfaces:${N}"
    for iface in wlan0 ap0 swlan0; do
        if run "ip link show $iface" &>/dev/null; then
            local state=$(run "ip link show $iface" | grep -o "state [A-Z]*" | cut -d' ' -f2)
            echo -e "$iface: ${state:-DOWN}"
        fi
    done
    
    read -p $'\nPress Enter to continue...'
}

# ═══════════════════════════════════════════════════
# MAIN MENU
# ═══════════════════════════════════════════════════
menu() {
    while true; do
        show
        
        echo -e "${C}1.${N} Show Connected Devices"
        echo -e "${C}2.${N} Speed Limit (50KB/s)"
        echo -e "${C}3.${N} Block Device"
        echo -e "${C}4.${N} Unblock Device"
        echo -e "${C}5.${N} Kick Device"
        echo -e "${C}6.${N} Reset All Settings"
        echo -e "${C}7.${N} Status Info"
        echo -e "${C}0.${N} Exit"
        
        read -p $'\nSelect option: ' choice
        
        case $choice in
            1)
                show
                echo -e "${C}══════ CONNECTED DEVICES ══════${N}\n"
                show_clients
                read -p $'\nPress Enter to continue...'
                ;;
            2) limit ;;
            3) block ;;
            4) unblock ;;
            5) kick ;;
            6) reset_all ;;
            7) info ;;
            0)
                echo -e "\n${C}By: senzore ganteng${N}\n"
                exit 0
                ;;
            *)
                echo -e "${R}Invalid option!${N}"
                sleep 1
                ;;
        esac
    done
}

# ═══════════════════════════════════════════════════
# MAIN STARTUP
# ═══════════════════════════════════════════════════
main() {
    show
    echo -e "${C}Initializing...${N}\n"
    
    # Check for root access
    check_root
    
    if [ $HAS_ROOT -eq 1 ]; then
        # Setup TTL and forwarding
        fix_ttl
        
        echo -e "\n${G}[✓] Ready!${N}"
        echo -e "${Y}TTL set to 65 (bypass detection)${N}"
    else
        echo -e "\n${R}Running without root!${N}"
        echo -e "${R}Most features will not work!${N}"
    fi
    
    sleep 2
    
    # Start menu
    menu
}

# START THE PROGRAM
main
