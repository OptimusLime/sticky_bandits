#!/usr/bin/env bash
# No set -e, we want to continue even if commands fail

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
iw dev "$AP_IFACE" info 2>/dev/null | grep -E "type|ssid|channel" || echo "    Could not get info"

echo ""
echo "[4b] Full interface info:"
iw dev "$AP_IFACE" info 2>/dev/null || echo "    Could not get info"

echo ""
echo "[4c] Is interface actually transmitting? (check txpower):"
iw dev "$AP_IFACE" info 2>/dev/null | grep -i txpower || echo "    No txpower info"

echo ""
echo "[4d] Interface link state:"
ip link show "$AP_IFACE" 2>/dev/null || echo "    Could not get link state"

echo ""
echo "[4e] Any errors in dmesg about this interface?"
dmesg 2>/dev/null | grep -i "$AP_IFACE" | tail -10 || echo "    No dmesg entries"

echo ""
echo "[4f] WiFiphy capabilities for this adapter:"
PHY=$(iw dev "$AP_IFACE" info 2>/dev/null | grep wiphy | awk '{print $2}')
if [[ -n "$PHY" ]]; then
  echo "    Checking phy$PHY bands and frequencies..."
  iw phy "phy$PHY" info 2>/dev/null | grep -A 50 "Frequencies:" | head -30 || true
fi

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
iw reg get 2>/dev/null | head -10 || echo "    Could not get regulatory domain"

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
echo "[22] Testing if traffic can flow from AP subnet to internet:"
echo "    Simulating packet from 192.168.60.x via iptables..."
# Check if MASQUERADE is working by verifying conntrack
if command -v conntrack >/dev/null 2>&1; then
  echo "    Recent NAT connections:"
  conntrack -L 2>/dev/null | grep "192.168.60" | head -5 || echo "    No NAT entries for 192.168.60.x"
else
  echo "    conntrack not installed, skipping"
fi

echo ""
echo "[23] Can we reach api.stickerbox.com from this host?"
echo "    DNS resolution:"
host api.stickerbox.com 2>/dev/null | head -3 || nslookup api.stickerbox.com 2>/dev/null | head -5 || echo "    DNS lookup failed"
echo "    HTTPS connectivity:"
curl -s -o /dev/null -w "    HTTP status: %{http_code}, Time: %{time_total}s\n" --connect-timeout 5 https://api.stickerbox.com/ 2>/dev/null || echo "    curl failed or timed out"

echo ""
echo "[24] Checking for blocked traffic in iptables:"
iptables -L -v -n 2>/dev/null | grep -E "DROP|REJECT" | head -10 || echo "    No DROP/REJECT rules found"

echo ""
echo "[25] Recent kernel network errors:"
dmesg 2>/dev/null | grep -iE "dropped|refused|unreachable|martian" | tail -5 || echo "    No recent errors"

echo ""
echo "=== End Diagnostic ==="
