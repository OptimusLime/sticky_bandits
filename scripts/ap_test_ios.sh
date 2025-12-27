#!/usr/bin/env bash
# iOS-compatible AP test
# Usage: sudo bash scripts/ap_test_ios.sh [channel] [--80211d]
#
# Options:
#   channel    WiFi channel (default: 1)
#   --80211d   Enable ieee80211d (country info in beacons)
#
# Examples:
#   sudo bash scripts/ap_test_ios.sh 1
#   sudo bash scripts/ap_test_ios.sh 6 --80211d

set -euo pipefail

die() { echo "[FATAL] $*" >&2; exit 1; }
info() { echo "[*] $*"; }

[[ "${EUID}" -eq 0 ]] || die "Run with sudo"

AP_IFACE="${AP_IFACE:-wlx00c0cab9645b}"
CHANNEL="1"
USE_80211D="0"
SSID="sticky_bandits"
PASSPHRASE="paulsworld"

# Parse args
for arg in "$@"; do
  case $arg in
    --80211d) USE_80211D="1" ;;
    [0-9]*) CHANNEL="$arg" ;;
  esac
done

info "iOS AP Test - Channel $CHANNEL, 802.11d=$USE_80211D"

# Stop everything
systemctl stop hostapd 2>/dev/null || true
systemctl stop dnsmasq 2>/dev/null || true
pkill -9 hostapd 2>/dev/null || true
sleep 1

# Set regulatory domain
iw reg set US 2>/dev/null || true

# Configure interface
nmcli dev set "$AP_IFACE" managed no 2>/dev/null || true
ip link set "$AP_IFACE" down 2>/dev/null || true
sleep 1
ip addr flush dev "$AP_IFACE" 2>/dev/null || true
ip addr add 192.168.60.1/24 dev "$AP_IFACE"
ip link set "$AP_IFACE" up
sleep 1

# Build config
cat > /etc/hostapd/hostapd.conf <<EOF
interface=$AP_IFACE
driver=nl80211
ssid=$SSID
hw_mode=g
channel=$CHANNEL
auth_algs=1
wpa=2
wpa_passphrase=$PASSPHRASE
wpa_key_mgmt=WPA-PSK
rsn_pairwise=CCMP
ignore_broadcast_ssid=0
EOF

# Optionally add 802.11d
if [[ "$USE_80211D" == "1" ]]; then
  echo "country_code=US" >> /etc/hostapd/hostapd.conf
  echo "ieee80211d=1" >> /etc/hostapd/hostapd.conf
fi

echo ""
echo "========================================"
echo "SSID: $SSID"
echo "Password: $PASSPHRASE"
echo "Channel: $CHANNEL"
echo "802.11d: $USE_80211D"
echo "========================================"
echo ""

hostapd -d /etc/hostapd/hostapd.conf
