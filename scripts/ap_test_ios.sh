#!/usr/bin/env bash
# Quick AP test for iOS compatibility
# Usage: sudo bash scripts/ap_test_ios.sh [channel]
#
# This script brings up a minimal AP and waits for you to test iOS visibility.
# Try channels 1, 6, or 11 if one doesn't work.

set -euo pipefail

die() { echo "[FATAL] $*" >&2; exit 1; }
info() { echo "[*] $*"; }
ok() { echo "[+] $*"; }

[[ "${EUID}" -eq 0 ]] || die "Run with sudo"

AP_IFACE="${AP_IFACE:-wlx00c0cab9645b}"
CHANNEL="${1:-6}"
SSID="sticky_bandits"
PASSPHRASE="paulsworld"
COUNTRY="US"

info "Testing iOS-compatible AP on channel $CHANNEL"

# Stop everything
systemctl stop hostapd 2>/dev/null || true
systemctl stop dnsmasq 2>/dev/null || true

# Set regulatory domain
info "Setting regulatory domain to $COUNTRY"
iw reg set "$COUNTRY"
sleep 1

# Show current reg domain
echo "Current regulatory domain:"
iw reg get | head -5

# Configure interface
info "Configuring $AP_IFACE..."
nmcli dev set "$AP_IFACE" managed no 2>/dev/null || true
ip link set "$AP_IFACE" down 2>/dev/null || true
sleep 1
ip addr flush dev "$AP_IFACE" 2>/dev/null || true
ip addr add 192.168.60.1/24 dev "$AP_IFACE"
ip link set "$AP_IFACE" up
sleep 1

# Write minimal hostapd config
cat > /etc/hostapd/hostapd.conf <<EOF
interface=$AP_IFACE
driver=nl80211
country_code=$COUNTRY
ieee80211d=1
ssid=$SSID
hw_mode=g
channel=$CHANNEL
ieee80211n=0
wmm_enabled=1
auth_algs=1
wpa=2
wpa_passphrase=$PASSPHRASE
wpa_key_mgmt=WPA-PSK
rsn_pairwise=CCMP
ignore_broadcast_ssid=0
EOF

echo "DAEMON_CONF=\"/etc/hostapd/hostapd.conf\"" > /etc/default/hostapd

# Start hostapd in foreground with debug
info "Starting hostapd on channel $CHANNEL (Ctrl+C to stop)..."
echo ""
echo "========================================"
echo "SSID: $SSID"
echo "Password: $PASSPHRASE" 
echo "Channel: $CHANNEL"
echo "========================================"
echo ""
echo "Check your iOS device NOW for the network."
echo "If not visible, try: sudo bash scripts/ap_test_ios.sh 1"
echo "Or try: sudo bash scripts/ap_test_ios.sh 11"
echo ""

# Run hostapd in foreground so we see all output
hostapd -d /etc/hostapd/hostapd.conf
