#!/usr/bin/env bash
# Quick AP test for iOS compatibility
# Usage: sudo bash scripts/ap_test_ios.sh [channel]
#
# This script uses linux-wifi-hotspot/create_ap which handles
# the DS params issue better than raw hostapd.

set -euo pipefail

die() { echo "[FATAL] $*" >&2; exit 1; }
info() { echo "[*] $*"; }
ok() { echo "[+] $*"; }

[[ "${EUID}" -eq 0 ]] || die "Run with sudo"

AP_IFACE="${AP_IFACE:-wlx00c0cab9645b}"
UPLINK_IFACE="${UPLINK_IFACE:-wlp6s0}"
CHANNEL="${1:-6}"
SSID="sticky_bandits"
PASSPHRASE="paulsworld"

# Check if create_ap is installed
if ! command -v create_ap &>/dev/null; then
    info "create_ap not found, installing linux-wifi-hotspot..."
    apt-get update
    apt-get install -y git build-essential hostapd iproute2 iw haveged dnsmasq
    
    cd /tmp
    rm -rf linux-wifi-hotspot
    git clone https://github.com/lakinduakash/linux-wifi-hotspot.git
    cd linux-wifi-hotspot
    make
    make install
    cd -
fi

# Stop any existing AP
info "Stopping existing services..."
systemctl stop hostapd 2>/dev/null || true
systemctl stop dnsmasq 2>/dev/null || true
pkill -f create_ap 2>/dev/null || true
sleep 2

# Set regulatory domain
info "Setting regulatory domain to US"
iw reg set US
sleep 1

# Release interface from NetworkManager
nmcli dev set "$AP_IFACE" managed no 2>/dev/null || true

echo ""
echo "========================================"
echo "Starting AP with create_ap"
echo "========================================"
echo ""
echo "SSID: $SSID"
echo "Password: $PASSPHRASE"
echo "Channel: $CHANNEL"
echo "AP Interface: $AP_IFACE"
echo "Uplink: $UPLINK_IFACE"
echo ""
echo "Check your iOS device NOW for the network."
echo "Press Ctrl+C to stop."
echo ""

# Run create_ap - it handles the DS params issue internally
create_ap --no-virt -c "$CHANNEL" "$AP_IFACE" "$UPLINK_IFACE" "$SSID" "$PASSPHRASE"
