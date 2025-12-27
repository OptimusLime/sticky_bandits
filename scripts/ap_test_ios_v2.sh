#!/usr/bin/env bash
# AP test v2 - tries to work around DS params filtering
# 
# The DS params mismatch happens because iOS sends probe requests
# with ds_params set to a different channel than we're on.
# hostapd ignores these by default.
#
# Workaround: Disable ieee80211d (country info) - this removes the
# DS params element from beacons which may help.

set -euo pipefail

die() { echo "[FATAL] $*" >&2; exit 1; }
info() { echo "[*] $*"; }
ok() { echo "[+] $*"; }

[[ "${EUID}" -eq 0 ]] || die "Run with sudo"

AP_IFACE="${AP_IFACE:-wlx00c0cab9645b}"
CHANNEL="${1:-1}"  # Default to channel 1 - iOS scans this first
SSID="sticky_bandits"
PASSPHRASE="paulsworld"

info "Testing iOS-compatible AP on channel $CHANNEL (no 802.11d)"

# Stop everything
systemctl stop hostapd 2>/dev/null || true
systemctl stop dnsmasq 2>/dev/null || true
pkill -9 hostapd 2>/dev/null || true
sleep 1

# Set regulatory domain anyway
iw reg set US 2>/dev/null || true

# Configure interface
info "Configuring $AP_IFACE..."
nmcli dev set "$AP_IFACE" managed no 2>/dev/null || true
ip link set "$AP_IFACE" down 2>/dev/null || true
sleep 1
ip addr flush dev "$AP_IFACE" 2>/dev/null || true
ip addr add 192.168.60.1/24 dev "$AP_IFACE"
ip link set "$AP_IFACE" up
sleep 1

# Write hostapd config WITHOUT ieee80211d
# This prevents the DS params check from being too strict
cat > /etc/hostapd/hostapd.conf <<EOF
interface=$AP_IFACE
driver=nl80211

# NO ieee80211d - this is key for the DS params workaround
# country_code and ieee80211d removed intentionally

ssid=$SSID
hw_mode=g
channel=$CHANNEL

# Keep it simple - no 802.11n
ieee80211n=0
wmm_enabled=1

# WPA2
auth_algs=1
wpa=2
wpa_passphrase=$PASSPHRASE
wpa_key_mgmt=WPA-PSK
rsn_pairwise=CCMP

# Broadcast SSID
ignore_broadcast_ssid=0
EOF

echo "DAEMON_CONF=\"/etc/hostapd/hostapd.conf\"" > /etc/default/hostapd

info "Starting hostapd on channel $CHANNEL WITHOUT 802.11d..."
echo ""
echo "========================================"
echo "SSID: $SSID"
echo "Password: $PASSPHRASE"
echo "Channel: $CHANNEL"
echo "NOTE: ieee80211d DISABLED"
echo "========================================"
echo ""
echo "Check your iOS device NOW."
echo ""

hostapd -d /etc/hostapd/hostapd.conf
