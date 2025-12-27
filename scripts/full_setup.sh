#!/usr/bin/env bash
# Full AP setup from scratch - reset, connect uplink, start AP
# Usage: sudo WIFI_PASS="yourpass" bash scripts/full_setup.sh

set -euo pipefail

die() { echo "[FATAL] $*" >&2; exit 1; }
info() { echo "[*] $*"; }
ok() { echo "[+] $*"; }

[[ "${EUID}" -eq 0 ]] || die "Run with sudo"

# Configuration - all passwords are paulsworld
HOME_SSID="${HOME_SSID:-YouMeshedWithTheWrongWifi}"
WIFI_PASS="${WIFI_PASS:-paulsworld}"
AP_SSID="${AP_SSID:-sticky_bandits}"
AP_PASS="${AP_PASS:-paulsworld}"
INTERNAL_IFACE="wlp6s0"
ALFA_IFACE="wlx00c0cab9645b"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

info "=== FULL AP SETUP ==="
info "Home WiFi: $HOME_SSID"
info "AP SSID: $AP_SSID"
info "Internal interface (uplink): $INTERNAL_IFACE"
info "Alfa interface (AP): $ALFA_IFACE"
echo ""

# --- STEP 1: Complete reset ---
info "Step 1: Resetting everything..."
bash "$REPO_ROOT/scripts/ap_reset.sh"

# --- STEP 2: Wait for interfaces to be ready ---
info "Step 2: Waiting for interfaces..."
sleep 3

# Make sure internal interface is up and managed
info "Bringing up $INTERNAL_IFACE..."
ip link set "$INTERNAL_IFACE" up 2>/dev/null || true
nmcli dev set "$INTERNAL_IFACE" managed yes 2>/dev/null || true
sleep 2

# --- STEP 3: Scan and connect to home WiFi ---
info "Step 3: Scanning for WiFi networks..."
MAX_ATTEMPTS=5
ATTEMPT=1
CONNECTED=false

while [[ $ATTEMPT -le $MAX_ATTEMPTS ]]; do
  info "Scan attempt $ATTEMPT/$MAX_ATTEMPTS..."
  nmcli dev wifi rescan ifname "$INTERNAL_IFACE" 2>/dev/null || true
  sleep 3
  
  if nmcli dev wifi list ifname "$INTERNAL_IFACE" 2>/dev/null | grep -q "$HOME_SSID"; then
    info "Found $HOME_SSID, connecting..."
    if nmcli dev wifi connect "$HOME_SSID" password "$WIFI_PASS" ifname "$INTERNAL_IFACE" 2>/dev/null; then
      CONNECTED=true
      break
    fi
  fi
  
  ATTEMPT=$((ATTEMPT + 1))
  sleep 2
done

if [[ "$CONNECTED" != "true" ]]; then
  echo ""
  echo "Available networks:"
  nmcli dev wifi list 2>/dev/null || true
  die "Failed to connect to $HOME_SSID after $MAX_ATTEMPTS attempts"
fi

ok "Connected to $HOME_SSID"

# --- STEP 4: Verify internet ---
info "Step 4: Verifying internet connectivity..."
sleep 2
if ! ping -c 2 -W 3 -I "$INTERNAL_IFACE" 8.8.8.8 >/dev/null 2>&1; then
  die "No internet on $INTERNAL_IFACE"
fi
ok "Internet working on $INTERNAL_IFACE"

# --- STEP 5: Start AP ---
info "Step 5: Starting AP on Alfa..."
AP_IFACE="$ALFA_IFACE" UPLINK_IFACE="$INTERNAL_IFACE" SSID="$AP_SSID" PASSPHRASE="$AP_PASS" \
  bash "$REPO_ROOT/scripts/ap_up.sh"

ok "=== SETUP COMPLETE ==="
echo ""
echo "Connect your devices to:"
echo "  SSID: $AP_SSID"
echo "  Password: $AP_PASS"
echo ""
