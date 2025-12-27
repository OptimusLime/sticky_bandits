#!/usr/bin/env bash
# Phase 2: Full setup + DNS hijack + intercept server
# 
# This script does EVERYTHING from scratch:
# 1. Runs full_setup.sh to get AP working
# 2. Adds DNS override for ws.stickerbox.com
# 3. Restarts dnsmasq with the override
# 4. Runs the intercept HTTPS server
# 5. Cleans up when done
#
# Usage: sudo bash scripts/phase2_intercept.sh

set -uo pipefail

die() { echo "[FATAL] $*" >&2; exit 1; }
info() { echo "[*] $*"; }
ok() { echo "[+] $*"; }

[[ "${EUID}" -eq 0 ]] || die "Run with sudo"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INTERCEPT_CONF="/etc/dnsmasq.d/intercept.conf"
GATEWAY_IP="192.168.60.1"

cleanup() {
    info "Cleaning up DNS override..."
    rm -f "$INTERCEPT_CONF"
    systemctl restart dnsmasq 2>/dev/null || true
    ok "DNS override removed"
}

trap cleanup EXIT

info "=== Phase 2: Full Setup + DNS Intercept ==="
echo ""

# Step 1: Run full setup from scratch
info "Running full AP setup..."
bash "$REPO_ROOT/scripts/full_setup.sh"

# Verify it worked
if ! systemctl is-active --quiet hostapd; then
    die "hostapd not running after setup"
fi
if ! systemctl is-active --quiet dnsmasq; then
    die "dnsmasq not running after setup"
fi
ok "AP is up and running"
echo ""

# Step 2: Add DNS override AFTER full setup is complete
info "Adding DNS override for ws.stickerbox.com -> $GATEWAY_IP"
cat > "$INTERCEPT_CONF" <<EOF
address=/ws.stickerbox.com/$GATEWAY_IP
EOF

# Step 3: Restart dnsmasq to pick up the new config
info "Restarting dnsmasq with intercept config..."
systemctl restart dnsmasq
sleep 2

if ! systemctl is-active --quiet dnsmasq; then
    journalctl -u dnsmasq --no-pager -n 10 || true
    die "dnsmasq failed after adding intercept config"
fi
ok "dnsmasq running with intercept"

# Step 3b: Verify AP is still working after dnsmasq restart
info "Verifying AP is still broadcasting..."
if ! iw dev wlx00c0cab9645b info 2>/dev/null | grep -q "type AP"; then
    iw dev wlx00c0cab9645b info || true
    die "AP interface is no longer in AP mode!"
fi

if ! iw dev wlx00c0cab9645b info 2>/dev/null | grep -q "ssid sticky_bandits"; then
    iw dev wlx00c0cab9645b info || true
    die "AP is not broadcasting SSID!"
fi
ok "AP still broadcasting sticky_bandits"

# Step 4: Verify
info "Verifying DNS override..."
RESOLVED=$(dig +short ws.stickerbox.com @127.0.0.1 2>/dev/null | head -1 || true)
if [[ "$RESOLVED" == "$GATEWAY_IP" ]]; then
    ok "ws.stickerbox.com -> $GATEWAY_IP"
else
    info "Got: $RESOLVED (device may need to reconnect to pick up new DNS)"
fi
echo ""

# Step 5: Generate fresh certs
rm -rf "$REPO_ROOT/certs"
mkdir -p "$REPO_ROOT/logs"

# Step 6: Run intercept server
echo "========================================"
ok "READY FOR INTERCEPT"
echo "========================================"
echo ""
echo "AP SSID: sticky_bandits"
echo "Password: paulsworld"
echo ""
echo "DNS hijack active: ws.stickerbox.com -> $GATEWAY_IP"
echo ""
echo "Connect the stickerbox device and trigger it."
echo "Watch for TLS connection attempts below."
echo ""
echo "Press Ctrl+C when done."
echo ""

python3 "$REPO_ROOT/scripts/intercept_server.py" --log-file "$REPO_ROOT/logs/intercept.log"

echo ""
info "Results in logs/intercept.log"
