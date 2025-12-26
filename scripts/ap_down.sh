#!/usr/bin/env bash
set -euo pipefail

if [[ "${EUID}" -ne 0 ]]; then
  echo "Run with sudo/root."
  exit 1
fi

AP_IFACE="${AP_IFACE:-wlan0}"
UPLINK_IFACE="${UPLINK_IFACE:-eth0}"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo "[*] Stopping capture (if running)..."
sudo bash "$REPO_ROOT/scripts/capture.sh" stop >/dev/null 2>&1 || true

echo "[*] Stopping services..."
systemctl stop hostapd >/dev/null 2>&1 || true
systemctl stop dnsmasq >/dev/null 2>&1 || true

echo "[*] Removing iptables chains (if present)..."
# Remove jumps if present
iptables -D FORWARD -j SB_FORWARD >/dev/null 2>&1 || true
iptables -F SB_FORWARD >/dev/null 2>&1 || true
iptables -X SB_FORWARD >/dev/null 2>&1 || true

iptables -t nat -D POSTROUTING -j SB_POSTROUTING >/dev/null 2>&1 || true
iptables -t nat -F SB_POSTROUTING >/dev/null 2>&1 || true
iptables -t nat -X SB_POSTROUTING >/dev/null 2>&1 || true

echo "[*] Leaving netplan + configs in place (remove if you want):"
echo "    /etc/netplan/99-sticky-bandits.yaml"
echo "    /etc/hostapd/hostapd.conf"
echo "    /etc/dnsmasq.d/sticky-bandits.conf"
echo
echo "[+] Down."
