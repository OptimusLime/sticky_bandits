#!/usr/bin/env bash
set -euo pipefail

# Undo everything ap_up.sh did and restore normal network

echo "[*] Removing sticky_bandits configs..."
rm -f /etc/netplan/99-sticky-bandits.yaml
rm -f /etc/dnsmasq.d/sticky-bandits.conf
rm -f /etc/dnsmasq.d/intercept.conf

echo "[*] Stopping hostapd and dnsmasq..."
systemctl stop hostapd || true
systemctl stop dnsmasq || true
systemctl disable hostapd || true
systemctl disable dnsmasq || true

echo "[*] Removing iptables rules..."
iptables -D FORWARD -j SB_FORWARD 2>/dev/null || true
iptables -F SB_FORWARD 2>/dev/null || true
iptables -X SB_FORWARD 2>/dev/null || true
iptables -t nat -D POSTROUTING -j SB_POSTROUTING 2>/dev/null || true
iptables -t nat -F SB_POSTROUTING 2>/dev/null || true
iptables -t nat -X SB_POSTROUTING 2>/dev/null || true

echo "[*] Letting NetworkManager manage wlp6s0 again..."
nmcli dev set wlp6s0 managed yes || true

echo "[*] Reapplying netplan..."
netplan apply || true

echo "[*] Restarting NetworkManager..."
systemctl restart NetworkManager || true

echo "[*] Restarting Tailscale..."
systemctl restart tailscaled || true

echo ""
echo "[+] Done. Now manually reconnect to WiFi:"
echo "    nmcli dev wifi connect \"YouMeshedWithTheWrongWifi\" password \"<pass>\" ifname wlp6s0"
echo ""
echo "Then verify:"
echo "    ping -c 2 8.8.8.8"
echo "    tailscale status"
