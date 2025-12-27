#!/usr/bin/env bash
set -euo pipefail

# Diagnose AP issues - comprehensive

echo "=== AP Diagnostic ==="
echo "Time: $(date)"
echo ""

AP_IFACE="${AP_IFACE:-wlx00c0cab9645b}"

echo "--- Interface: $AP_IFACE ---"
echo ""

echo "[1] Interface exists?"
if ip link show "$AP_IFACE" >/dev/null 2>&1; then
  echo "    YES"
else
  echo "    NO - interface not found!"
  exit 1
fi

echo ""
echo "[2] Interface state:"
ip link show "$AP_IFACE" | head -2

echo ""
echo "[3] Interface IP address:"
ip addr show "$AP_IFACE" | grep inet || echo "    NO IP ADDRESS ASSIGNED"

echo ""
echo "[4] Interface mode (should be 'type AP'):"
iw dev "$AP_IFACE" info 2>/dev/null | grep -E "type|ssid" || echo "    Could not get info"

echo ""
echo "[5] Does this chipset support AP mode?"
PHY=$(iw dev "$AP_IFACE" info 2>/dev/null | grep wiphy | awk '{print $2}')
if [[ -n "$PHY" ]]; then
  echo "    PHY: phy$PHY"
  if iw phy "phy$PHY" info | grep -A20 "Supported interface modes" | grep -q "\* AP"; then
    echo "    AP mode: SUPPORTED"
  else
    echo "    AP mode: NOT SUPPORTED - this adapter cannot do AP mode!"
  fi
else
  echo "    Could not determine PHY"
fi

echo ""
echo "[6] Regulatory domain:"
iw reg get | head -10

echo ""
echo "[7] hostapd status:"
if systemctl is-active --quiet hostapd; then
  echo "    RUNNING"
else
  echo "    NOT RUNNING"
  echo "    Attempting to show why:"
  systemctl status hostapd --no-pager 2>&1 | head -20 || true
fi

echo ""
echo "[8] hostapd config:"
if [[ -f /etc/hostapd/hostapd.conf ]]; then
  cat /etc/hostapd/hostapd.conf
else
  echo "    No config file!"
fi

echo ""
echo "[9] hostapd logs (last 50 lines):"
journalctl -u hostapd --no-pager -n 50 2>/dev/null || echo "    No logs"

echo ""
echo "[10] dnsmasq status:"
if systemctl is-active --quiet dnsmasq; then
  echo "    RUNNING"
else
  echo "    NOT RUNNING"
  echo "    Attempting to show why:"
  systemctl status dnsmasq --no-pager 2>&1 | head -20 || true
fi

echo ""
echo "[11] dnsmasq config:"
if [[ -f /etc/dnsmasq.d/sticky-bandits.conf ]]; then
  cat /etc/dnsmasq.d/sticky-bandits.conf
else
  echo "    No config file!"
fi

echo ""
echo "[12] dnsmasq logs (last 50 lines):"
journalctl -u dnsmasq --no-pager -n 50 2>/dev/null || echo "    No logs"

echo ""
echo "[13] Current DHCP leases:"
if [[ -f /var/lib/misc/dnsmasq.leases ]]; then
  cat /var/lib/misc/dnsmasq.leases
  echo ""
  echo "    Lease count: $(wc -l < /var/lib/misc/dnsmasq.leases)"
else
  echo "    No leases file"
fi

echo ""
echo "[14] NetworkManager status for all wifi interfaces:"
nmcli dev status | grep -E "wifi|DEVICE" || echo "    Could not get status"

echo ""
echo "[15] Is NetworkManager managing $AP_IFACE? (should be 'unmanaged' or 'disconnected'):"
nmcli dev show "$AP_IFACE" 2>/dev/null | grep -E "GENERAL.STATE|GENERAL.CONNECTION" || echo "    Not listed"

echo ""
echo "[16] iptables NAT rules:"
iptables -t nat -S 2>/dev/null | grep -E "SB_|MASQUERADE" || echo "    No NAT rules found"

echo ""
echo "[17] iptables FORWARD rules:"
iptables -S FORWARD 2>/dev/null | head -10 || echo "    No FORWARD rules"
iptables -S SB_FORWARD 2>/dev/null || echo "    No SB_FORWARD chain"

echo ""
echo "[18] IP forwarding enabled?"
FORWARD=$(cat /proc/sys/net/ipv4/ip_forward)
if [[ "$FORWARD" == "1" ]]; then
  echo "    YES"
else
  echo "    NO - this will break routing!"
fi

echo ""
echo "[19] Route table:"
ip route | head -10

echo ""
echo "[20] Uplink interface status:"
UPLINK="${UPLINK_IFACE:-wlp6s0}"
echo "    Checking: $UPLINK"
ip addr show "$UPLINK" 2>/dev/null | grep -E "state|inet" || echo "    Interface not found"

echo ""
echo "[21] Can uplink reach internet?"
if ping -c 1 -W 2 -I "$UPLINK" 8.8.8.8 >/dev/null 2>&1; then
  echo "    YES - ping to 8.8.8.8 succeeded"
else
  echo "    NO - cannot reach 8.8.8.8 via $UPLINK"
fi

echo ""
echo "=== End Diagnostic ==="
