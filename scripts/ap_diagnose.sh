#!/usr/bin/env bash
set -euo pipefail

# Diagnose AP issues

echo "=== AP Diagnostic ==="
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
echo "[3] Interface mode (should be 'type AP'):"
iw dev "$AP_IFACE" info 2>/dev/null | grep -E "type|ssid" || echo "    Could not get info"

echo ""
echo "[4] Does this chipset support AP mode?"
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
echo "[5] Regulatory domain:"
iw reg get | head -5

echo ""
echo "[6] hostapd status:"
systemctl is-active hostapd && echo "    Running" || echo "    Not running"

echo ""
echo "[7] hostapd config:"
if [[ -f /etc/hostapd/hostapd.conf ]]; then
  cat /etc/hostapd/hostapd.conf
else
  echo "    No config file!"
fi

echo ""
echo "[8] hostapd recent logs:"
journalctl -u hostapd --no-pager -n 30 2>/dev/null || echo "    No logs"

echo ""
echo "[9] dnsmasq status:"
systemctl is-active dnsmasq && echo "    Running" || echo "    Not running"

echo ""
echo "[10] Current DHCP leases:"
cat /var/lib/misc/dnsmasq.leases 2>/dev/null || echo "    No leases file"

echo ""
echo "[11] Checking for interfering processes:"
ps aux | grep -E "wpa_supplicant|NetworkManager" | grep -v grep || echo "    None found"

echo ""
echo "[12] Is NetworkManager managing this interface?"
nmcli dev status | grep "$AP_IFACE" || echo "    Not listed"

echo ""
echo "=== End Diagnostic ==="
