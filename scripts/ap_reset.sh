#!/usr/bin/env bash
set -euo pipefail

# Undo everything ap_up.sh did and restore normal network
# Safe to run multiple times

info() { echo "[*] $*"; }
ok() { echo "[+] $*"; }

AP_IFACE="${AP_IFACE:-wlp6s0}"

info "Stopping services..."
systemctl stop hostapd 2>/dev/null || true
systemctl stop dnsmasq 2>/dev/null || true
systemctl disable hostapd 2>/dev/null || true
systemctl disable dnsmasq 2>/dev/null || true

info "Removing config files..."
rm -f /etc/netplan/99-sticky-bandits.yaml
rm -f /etc/dnsmasq.d/sticky-bandits.conf
rm -f /etc/dnsmasq.d/intercept.conf
rm -f /etc/sysctl.d/99-sticky-bandits.conf

info "Removing iptables rules..."
iptables -D FORWARD -j SB_FORWARD 2>/dev/null || true
iptables -F SB_FORWARD 2>/dev/null || true
iptables -X SB_FORWARD 2>/dev/null || true
iptables -t nat -D POSTROUTING -j SB_POSTROUTING 2>/dev/null || true
iptables -t nat -F SB_POSTROUTING 2>/dev/null || true
iptables -t nat -X SB_POSTROUTING 2>/dev/null || true

info "Resetting $AP_IFACE..."
ip addr flush dev "$AP_IFACE" 2>/dev/null || true
ip link set "$AP_IFACE" down 2>/dev/null || true

info "Returning $AP_IFACE to NetworkManager..."
nmcli dev set "$AP_IFACE" managed yes 2>/dev/null || true

info "Restarting NetworkManager..."
systemctl restart NetworkManager || true

info "Waiting for NetworkManager to settle..."
sleep 3

info "Restarting Tailscale..."
systemctl restart tailscaled 2>/dev/null || true

ok "Reset complete."
echo ""
echo "Your WiFi interfaces:"
nmcli dev status | grep -E "wifi|DEVICE" || true
echo ""
echo "To reconnect to home WiFi (if needed):"
echo "    sudo nmcli dev wifi connect \"<SSID>\" password \"<pass>\" ifname <interface>"
echo ""
echo "To verify internet:"
echo "    ping -c 2 8.8.8.8"
