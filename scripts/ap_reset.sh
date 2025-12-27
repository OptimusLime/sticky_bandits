#!/usr/bin/env bash
# No set -e, we want to continue even if commands fail

# Complete reset of AP setup - restores normal network state

info() { echo "[*] $*"; }
ok() { echo "[+] $*"; }

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
rm -f /var/lib/misc/dnsmasq.leases

info "Removing iptables rules..."
iptables -D FORWARD -j SB_FORWARD 2>/dev/null || true
iptables -F SB_FORWARD 2>/dev/null || true
iptables -X SB_FORWARD 2>/dev/null || true
iptables -t nat -D POSTROUTING -j SB_POSTROUTING 2>/dev/null || true
iptables -t nat -F SB_POSTROUTING 2>/dev/null || true
iptables -t nat -X SB_POSTROUTING 2>/dev/null || true

info "Resetting ALL wifi interfaces..."
# Find all wifi interfaces and reset them
for IFACE in $(iw dev 2>/dev/null | grep Interface | awk '{print $2}'); do
  info "  Resetting $IFACE..."
  ip addr flush dev "$IFACE" 2>/dev/null || true
  ip link set "$IFACE" down 2>/dev/null || true
  ip link set "$IFACE" up 2>/dev/null || true
  nmcli dev set "$IFACE" managed yes 2>/dev/null || true
done

info "Restarting NetworkManager..."
systemctl restart NetworkManager || true

info "Waiting for NetworkManager to settle..."
sleep 3

info "Scanning for wifi networks..."
for IFACE in $(iw dev 2>/dev/null | grep Interface | awk '{print $2}'); do
  nmcli dev wifi rescan ifname "$IFACE" 2>/dev/null || true
done
sleep 3

info "Restarting Tailscale..."
systemctl restart tailscaled 2>/dev/null || true

ok "Reset complete."
echo ""
echo "Available wifi networks:"
nmcli dev wifi list 2>/dev/null | head -20 || true
echo ""
echo "Current interface status:"
nmcli dev status | grep -E "wifi|DEVICE" || true
echo ""
