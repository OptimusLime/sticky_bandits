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
AP_ADDR="192.168.60.1"

# Parse args
for arg in "$@"; do
  case $arg in
    --80211d) USE_80211D="1" ;;
    [0-9]*) CHANNEL="$arg" ;;
  esac
done

info "iOS AP Test - Channel $CHANNEL, 802.11d=$USE_80211D"

# Cleanup function
cleanup() {
  info "Cleaning up..."
  pkill -9 hostapd 2>/dev/null || true
  pkill -9 dnsmasq 2>/dev/null || true
}
trap cleanup EXIT

# Kill everything that could hold the interface
info "Killing interfering processes..."
systemctl stop hostapd 2>/dev/null || true
systemctl stop dnsmasq 2>/dev/null || true
systemctl stop NetworkManager 2>/dev/null || true
pkill -9 hostapd 2>/dev/null || true
pkill -9 dnsmasq 2>/dev/null || true
pkill -9 wpa_supplicant 2>/dev/null || true
rfkill unblock wifi 2>/dev/null || true
sleep 1

# Set regulatory domain
iw reg set US 2>/dev/null || true

# Configure interface - let hostapd set AP mode
info "Configuring interface..."
ip link set "$AP_IFACE" down
sleep 1
iw dev "$AP_IFACE" set type managed
sleep 1
ip addr flush dev "$AP_IFACE" 2>/dev/null || true
ip addr add "$AP_ADDR/24" dev "$AP_IFACE"
ip link set "$AP_IFACE" up
sleep 1

# Create control interface dir
mkdir -p /var/run/hostapd

# Build hostapd config
cat > /etc/hostapd/hostapd.conf <<EOF
interface=$AP_IFACE
driver=nl80211
ssid=$SSID
hw_mode=g
channel=$CHANNEL

# Auth - WPA1+WPA2 mixed mode for mt76 compatibility
auth_algs=1
wpa=3
wpa_passphrase=$PASSPHRASE
wpa_key_mgmt=WPA-PSK
wpa_pairwise=TKIP CCMP
rsn_pairwise=CCMP

# Required for iOS
wmm_enabled=1

# Broadcast
ignore_broadcast_ssid=0

# Control interface
ctrl_interface=/var/run/hostapd
ctrl_interface_group=0

# nl80211 driver options for mt76
ieee80211n=1
ht_capab=[HT40+][SHORT-GI-40][TX-STBC][RX-STBC1]

# Logging
logger_syslog=-1
logger_syslog_level=2
EOF

# Optionally add 802.11d
if [[ "$USE_80211D" == "1" ]]; then
  echo "country_code=US" >> /etc/hostapd/hostapd.conf
  echo "ieee80211d=1" >> /etc/hostapd/hostapd.conf
fi

# Start dnsmasq for DHCP
info "Starting DHCP server..."
cat > /tmp/dnsmasq-ios.conf <<EOF
interface=$AP_IFACE
bind-interfaces
dhcp-range=192.168.60.10,192.168.60.100,12h
dhcp-option=3,$AP_ADDR
dhcp-option=6,$AP_ADDR
log-dhcp
EOF

dnsmasq -C /tmp/dnsmasq-ios.conf -d &
DNSMASQ_PID=$!
sleep 1

if ! kill -0 $DNSMASQ_PID 2>/dev/null; then
  die "dnsmasq failed to start"
fi
info "DHCP running (PID $DNSMASQ_PID)"

echo ""
echo "========================================"
echo "SSID: $SSID"
echo "Password: $PASSPHRASE"
echo "Channel: $CHANNEL"
echo "Gateway: $AP_ADDR"
echo "DHCP: 192.168.60.10 - 100"
echo "========================================"
echo ""

hostapd -d /etc/hostapd/hostapd.conf
