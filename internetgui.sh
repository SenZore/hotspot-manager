#!/data/data/com.termux/files/usr/bin/bash

# ═══════════════════════════════════════════════════
# HOTSPOT MANAGER v13.0 - NEW APPROACH
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

# ═══════════════════════════════════════════════════
# SIMPLE BANNER
# ═══════════════════════════════════════════════════
show() {
    clear
    echo -e "${C}═══════════════════════════════════════════════════${N}"
    echo -e "${C}         HOTSPOT MANAGER v13.0${N}"
    echo -e "${C}         By: senzore ganteng${N}"
    echo -e "${C}═══════════════════════════════════════════════════${N}\n"
}

# ═══════════════════════════════════════════════════
# ROOT CHECK - DIFFERENT METHOD
# ═══════════════════════════════════════════════════
need_root() {
    # Try different root methods
    local root_ok=0
    
    # Method 1: Direct su test
    if timeout 2 su -c "echo test" >/dev/null 2>&1; then
        root_ok=1
    fi
    
    # Method 2: Check if we can write to system
    if [ $root_ok -eq 0 ]; then
        if timeout 2 su 0 sh -c "echo test" >/dev/null 2>&1; then
            root_ok=1
        fi
    fi
    
    if [ $root_ok -eq 1 ]; then
        echo -e "${G}Root: OK${N}"
        return 0
    else
        echo -e "${R}Root: FAILED${N}"
        echo -e "${Y}This app needs root!${N}"
        exit 1
    fi
}

# ═══════════════════════════════════════════════════
# RUN AS ROOT - WRAPPER
# ═══════════════════════════════════════════════════
run() {
    su -c "$1" 2>/dev/null || su 0 sh -c "$1" 2>/dev/null
}

# ═══════════════════════════════════════════════════
# SET TTL - NEW METHOD
# ═══════════════════════════════════════════════════
fix_ttl() {
    echo -e "${Y}Setting TTL to 65...${N}"
    
    # Method 1: sysctl
    run "sysctl -w net.ipv4.ip_default_ttl=65"
    
    # Method 2: Direct write
    run "echo 65 > /proc/sys/net/ipv4/ip_default_ttl"
    
    # Method 3: iptables mangle
    run "iptables -t mangle -D POSTROUTING -j TTL --ttl-set 65" 
    run "iptables -t mangle -A POSTROUTING -j TTL --ttl-set 65"
    
    # Enable forwarding
    run "sysctl -w net.ipv4.ip_forward=1"
    run "echo 1 > /proc/sys/net/ipv4/ip_forward"
    
    echo -e "${G}TTL set to 65${N}"
}

# ═══════════════════════════════════════════════════
# GET CLIENTS - NEW METHOD
# ═══════════════════════════════════════════════════
get_ips() {
    # Method 1: From dhcp leases
    local ips=$(run "cat /data/misc/dhcp/dnsmasq.leases 2>/dev/null | awk '{print \$3}'" | grep -E '^[0-9]+\.')
    
    # Method 2: From arp
    if [ -z "$ips" ]; then
        ips=$(run "arp -an 2>/dev/null | grep -v incomplete | awk '{print \$2}' | tr -d '()'" | grep -E '^[0-9]+\.')
    fi
    
    # Method 3: From ip neigh
    if [ -z "$ips" ]; then
        ips=$(run "ip neigh show 2>/dev/null | awk '{print \$1}'" | grep -E '^[0-9]+\.')
    fi
    
    # Method 4: From /proc/net/arp
    if [ -z "$ips" ]; then
        ips=$(run "cat /proc/net/arp 2>/dev/null | tail -n +2 | awk '{print \$1}'" | grep -E '^[0-9]+\.')
    fi
    
    echo "$ips" | sort -u | grep -v '^$'
}

# ═══════════════════════════════════════════════════
# SHOW CLIENTS
# ═══════════════════════════════════════════════════
show_clients() {
    echo -e "${Y}Scanning...${N}\n"
    
    local ips=$(get_ips)
    
    if [ -z "$ips" ]; then
        echo -e "${R}No devices found${N}"
        echo -e "${Y}Make sure hotspot is ON${N}"
        return 1
    fi
    
    local n=1
    echo "$ips" > "$DIR/clients.tmp"
    
    while read ip; do
        [ -z "$ip" ] && continue
        echo -e "${C}$n.${N} $ip"
        ((n++))
    done <<< "$ips"
    
    return 0
}

# ═══════════════════════════════════════════════════
# SPEED LIMIT - COMPLETELY NEW METHOD
# ═══════════════════════════════════════════════════
limit() {
    show
    echo -e "${C}══════ SPEED LIMIT ══════${N}\n"
    
    show_clients || { sleep 2; return; }
    
    echo -e "\n${G}Options:${N}"
    echo -e "${Y}0${N} = Limit ALL devices"
    echo -e "${Y}99${N} = Remove ALL limits"
    echo -e "${Y}1-X${N} = Select device"
    
    read -p $'\nChoice: ' num
    
    # Remove all
    if [ "$num" = "99" ]; then
        echo -e "\n${Y}Removing limits...${N}"
        
        # Clear iptables
        run "iptables -t mangle -F"
        run "iptables -t filter -F FORWARD"
        
        # Clear tc on all interfaces
        for i in wlan0 ap0 swlan0; do
            run "tc qdisc del dev $i root" 
            run "tc qdisc del dev $i ingress"
        done
        
        echo -e "${G}Limits removed${N}"
        sleep 2
        return
    fi
    
    # Get target IPs
    local targets=""
    if [ "$num" = "0" ]; then
        targets=$(cat "$DIR/clients.tmp")
        echo -e "\n${Y}Limiting ALL...${N}"
    else
        targets=$(sed -n "${num}p" "$DIR/clients.tmp")
        [ -z "$targets" ] && echo -e "${R}Invalid${N}" && sleep 2 && return
        echo -e "\n${Y}Limiting $targets...${N}"
    fi
    
    # Apply limits using iptables hashlimit
    while read ip; do
        [ -z "$ip" ] && continue
        
        # Method 1: hashlimit (50KB/s = 400kbit)
        run "iptables -I FORWARD -d $ip -m hashlimit --hashlimit-above 50kb/s --hashlimit-mode dstip --hashlimit-name down_$ip -j DROP"
        run "iptables -I FORWARD -s $ip -m hashlimit --hashlimit-above 50kb/s --hashlimit-mode srcip --hashlimit-name up_$ip -j DROP"
        
        # Method 2: limit module
        run "iptables -I FORWARD -d $ip -m limit --limit 100/s --limit-burst 50 -j ACCEPT"
        run "iptables -I FORWARD -d $ip -j DROP"
        
        echo -e "${G}Limited: $ip${N}"
    done <<< "$targets"
    
    sleep 2
}

# ═══════════════════════════════════════════════════
# BLOCK - SIMPLE METHOD
# ═══════════════════════════════════════════════════
block() {
    show
    echo -e "${C}══════ BLOCK ══════${N}\n"
    
    show_clients || { sleep 2; return; }
    
    read -p $'\nBlock which? ' num
    
    local ip=$(sed -n "${num}p" "$DIR/clients.tmp")
    
    if [ -n "$ip" ]; then
        echo -e "\n${Y}Blocking $ip...${N}"
        
        # Multiple methods to ensure blocking
        run "iptables -I INPUT -s $ip -j DROP"
        run "iptables -I OUTPUT -d $ip -j DROP"
        run "iptables -I FORWARD -s $ip -j DROP"
        run "iptables -I FORWARD -d $ip -j DROP"
        
        # Save to list
        echo "$ip" >> "$DIR/blocked"
        
        echo -e "${G}Blocked${N}"
    else
        echo -e "${R}Invalid${N}"
    fi
    
    sleep 2
}

# ═══════════════════════════════════════════════════
# UNBLOCK
# ═══════════════════════════════════════════════════
unblock() {
    show
    echo -e "${C}══════ UNBLOCK ══════${N}\n"
    
    if [ ! -s "$DIR/blocked" ]; then
        echo -e "${R}No blocked devices${N}"
        sleep 2
        return
    fi
    
    echo -e "${Y}Blocked:${N}\n"
    
    local n=1
    while read ip; do
        [ -z "$ip" ] && continue
        echo -e "${C}$n.${N} $ip"
        ((n++))
    done < "$DIR/blocked"
    
    read -p $'\nUnblock which? ' num
    
    local ip=$(sed -n "${num}p" "$DIR/blocked")
    
    if [ -n "$ip" ]; then
        echo -e "\n${Y}Unblocking $ip...${N}"
        
        run "iptables -D INPUT -s $ip -j DROP"
        run "iptables -D OUTPUT -d $ip -j DROP"
        run "iptables -D FORWARD -s $ip -j DROP"
        run "iptables -D FORWARD -d $ip -j DROP"
        
        # Remove from file
        sed -i "/^$ip$/d" "$DIR/blocked"
        
        echo -e "${G}Unblocked${N}"
    else
        echo -e "${R}Invalid${N}"
    fi
    
    sleep 2
}

# ═══════════════════════════════════════════════════
# KICK - NEW METHOD
# ═══════════════════════════════════════════════════
kick() {
    show
    echo -e "${C}══════ KICK ══════${N}\n"
    
    show_clients || { sleep 2; return; }
    
    read -p $'\nKick which? ' num
    
    local ip=$(sed -n "${num}p" "$DIR/clients.tmp")
    
    if [ -n "$ip" ]; then
        echo -e "\n${Y}Kicking $ip...${N}"
        
        # Deauth methods
        run "arp -d $ip"
        
        # Find interface
        for i in wlan0 ap0 swlan0; do
            run "ip neigh del $ip dev $i"
        done
        
        # Temp block
        run "iptables -I INPUT -s $ip -j DROP"
        
        sleep 3
        
        run "iptables -D INPUT -s $ip -j DROP"
        
        echo -e "${G}Kicked${N}"
    else
        echo -e "${R}Invalid${N}"
    fi
    
    sleep 2
}

# ═══════════════════════════════════════════════════
# FIX ALL
# ═══════════════════════════════════════════════════
fix_all() {
    show
    echo -e "${C}══════ FIX ALL ══════${N}\n"
    
    echo -e "${Y}Fixing everything...${N}\n"
    
    # Clear all rules
    echo "Clearing rules..."
    run "iptables -F"
    run "iptables -t nat -F"
    run "iptables -t mangle -F"
    run "iptables -X"
    
    # Reset policies
    echo "Reset policies..."
    run "iptables -P INPUT ACCEPT"
    run "iptables -P FORWARD ACCEPT"
    run "iptables -P OUTPUT ACCEPT"
    
    # Enable forwarding
    echo "Enable forwarding..."
    run "echo 1 > /proc/sys/net/ipv4/ip_forward"
    
    # Set TTL
    echo "Set TTL..."
    run "echo 65 > /proc/sys/net/ipv4/ip_default_ttl"
    run "iptables -t mangle -A POSTROUTING -j TTL --ttl-set 65"
    
    # NAT for hotspot
    echo "Setup NAT..."
    run "iptables -t nat -A POSTROUTING -j MASQUERADE"
    
    # Clear tc
    echo "Clear bandwidth..."
    for i in wlan0 ap0 swlan0; do
        run "tc qdisc del dev $i root"
        run "tc qdisc del dev $i ingress" 
    done
    
    # Clear files
    > "$DIR/blocked"
    
    echo -e "\n${G}Everything fixed!${N}"
    echo -e "${G}TTL: 65${N}"
    echo -e "${G}Forwarding: ON${N}"
    echo -e "${G}All limits: OFF${N}"
    
    sleep 3
}

# ═══════════════════════════════════════════════════
# INFO
# ═══════════════════════════════════════════════════
info() {
    show
    echo -e "${C}══════ INFO ══════${N}\n"
    
    echo -e "${Y}System:${N}"
    echo "TTL: $(cat /proc/sys/net/ipv4/ip_default_ttl 2>/dev/null || echo '?')"
    echo "Forward: $(cat /proc/sys/net/ipv4/ip_forward 2>/dev/null || echo '?')"
    
    echo -e "\n${Y}Devices:${N}"
    local count=$(get_ips | wc -l)
    echo "$count connected"
    
    if [ -s "$DIR/blocked" ]; then
        echo -e "\n${Y}Blocked:${N}"
        cat "$DIR/blocked"
    fi
    
    read -p $'\nPress Enter...'
}

# ═══════════════════════════════════════════════════
# MENU
# ═══════════════════════════════════════════════════
menu() {
    while true; do
        show
        
        echo -e "${C}1.${N} Show Devices"
        echo -e "${C}2.${N} Speed Limit (50KB/s)"
        echo -e "${C}3.${N} Block Device"
        echo -e "${C}4.${N} Unblock Device"
        echo -e "${C}5.${N} Kick Device"
        echo -e "${C}6.${N} Fix Everything"
        echo -e "${C}7.${N} Info"
        echo -e "${C}0.${N} Exit"
        
        read -p $'\nChoice: ' ch
        
        case $ch in
            1)
                show
                echo -e "${C}══════ DEVICES ══════${N}\n"
                show_clients
                read -p $'\nPress Enter...'
                ;;
            2) limit ;;
            3) block ;;
            4) unblock ;;
            5) kick ;;
            6) fix_all ;;
            7) info ;;
            0)
                echo -e "\n${C}By: senzore ganteng${N}\n"
                exit 0
                ;;
        esac
    done
}

# ═══════════════════════════════════════════════════
# START
# ═══════════════════════════════════════════════════
show
echo -e "${C}Starting...${N}\n"

need_root
fix_ttl

echo -e "\n${G}Ready!${N}"
sleep 2

menu
