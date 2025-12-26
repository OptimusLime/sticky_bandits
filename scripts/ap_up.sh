#!/usr/bin/env bash
set -euo pipefail

require_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    echo "Run with sudo/root."
    exit 1
  fi
}

have_cmd() { command -v "$1" >/dev/null 2>&1; }

AP_IFACE="${AP_IFACE:-wlan0}"
UPLINK_IFACE="${UPLINK_IFACE:-eth0}"
SSID="${SSID:-sticky_bandits}"
PASSPHRASE="${PASSPHRASE:-change-me-now-please}"
CHANNEL="${CHANNEL:-6}"

# Network config for AP side
AP_ADDR="${AP_ADDR:-192.168.50.1}"
CIDR="${CIDR:-24}"
DHCP_START="${DHCP_START:-192.168.50.10}"
DHCP_END="${DHCP_END:-192.168.50.100}"
LEASE_TIME="${LEASE_TIME:-12h}"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STATE_DIR="$REPO_ROOT/.state"
mkdir -p "$STATE_DIR"

require_root

echo "[*] sticky_bandits AP bring-up"
echo "    AP_IFACE=$AP_IFACE"
echo "    UPLINK_IFACE=$UPLINK_IFACE"
echo "    SSID=$SSID"
echo "    CHANNEL=$CHANNEL"
echo "    AP_ADDR=$AP_ADDR/$CIDR"

# Basic checks
ip link show "$AP_IFACE" >/dev/null
ip link show "$UPLINK_IFACE" >/dev/null

if have_cmd iw; then
  if ! iw list | grep -A20 "Supported interface modes" | grep -qE "^\s*\*\s*AP\b"; then
    echo "[!] Your wifi chipset may not support AP mode (iw list does not show '* AP')."
    echo "    Continuing anyway (some drivers lie), but hostapd may fail."
  fi
fi

# Create / update netplan config for AP interface.
NETPLAN_FILE="/etc/netplan/99-sticky-bandits.yaml"
echo "[*] Writing netplan: $NETPLAN_FILE"
sed \
  -e "s/{{AP_IFACE}}/$AP_IFACE/g" \
  -e "s/{{AP_ADDR}}/$AP_ADDR/g" \
  -e "s/{{CIDR}}/$CIDR/g" \
  "$REPO_ROOT/config/netplan-99-sticky-bandits.yaml.template" | tee "$NETPLAN_FILE" >/dev/null

echo "[*] Applying netplan..."
netplan apply

# hostapd config
HOSTAPD_CONF="/etc/hostapd/hostapd.conf"
echo "[*] Writing hostapd config: $HOSTAPD_CONF"
sed \
  -e "s/{{AP_IFACE}}/$AP_IFACE/g" \
  -e "s/{{SSID}}/$SSID/g" \
  -e "s/{{PASSPHRASE}}/$PASSPHRASE/g" \
  -e "s/{{CHANNEL}}/$CHANNEL/g" \
  "$REPO_ROOT/config/hostapd.conf.template" | tee "$HOSTAPD_CONF" >/dev/null

# Ensure /etc/default/hostapd points to our conf
DEFAULT_HOSTAPD="/etc/default/hostapd"
echo "[*] Pointing hostapd to $HOSTAPD_CONF via $DEFAULT_HOSTAPD"
if [[ -f "$DEFAULT_HOSTAPD" ]]; then
  if grep -q '^DAEMON_CONF=' "$DEFAULT_HOSTAPD"; then
    sed -i "s|^DAEMON_CONF=.*|DAEMON_CONF=\"$HOSTAPD_CONF\"|g" "$DEFAULT_HOSTAPD"
  else
    echo "DAEMON_CONF=\"$HOSTAPD_CONF\"" >> "$DEFAULT_HOSTAPD"
  fi
else
  echo "DAEMON_CONF=\"$HOSTAPD_CONF\"" > "$DEFAULT_HOSTAPD"
fi

# dnsmasq config (use drop-in to avoid clobbering global config)
DNSMASQ_DROPIN="/etc/dnsmasq.d/sticky-bandits.conf"
echo "[*] Writing dnsmasq config: $DNSMASQ_DROPIN"
sed \
  -e "s/{{AP_IFACE}}/$AP_IFACE/g" \
  -e "s/{{DHCP_START}}/$DHCP_START/g" \
  -e "s/{{DHCP_END}}/$DHCP_END/g" \
  -e "s/{{LEASE_TIME}}/$LEASE_TIME/g" \
  -e "s/{{AP_ADDR}}/$AP_ADDR/g" \
  "$REPO_ROOT/config/dnsmasq.conf.template" | tee "$DNSMASQ_DROPIN" >/dev/null

# Enable forwarding (immediate + persistent)
echo "[*] Enabling IPv4 forwarding"
echo 1 > /proc/sys/net/ipv4/ip_forward
SYSCTL_DROPIN="/etc/sysctl.d/99-sticky-bandits.conf"
echo "net.ipv4.ip_forward=1" > "$SYSCTL_DROPIN"
sysctl -p "$SYSCTL_DROPIN" >/dev/null || true

# Set up iptables with dedicated chains so we can cleanly remove later.
echo "[*] Configuring iptables NAT + forwarding (dedicated chains)"
# Filter table chain
iptables -N SB_FORWARD 2>/dev/null || true
iptables -F SB_FORWARD
# Ensure jump exists once at top
if ! iptables -C FORWARD -j SB_FORWARD 2>/dev/null; then
  iptables -I FORWARD 1 -j SB_FORWARD
fi

# SB_FORWARD rules
iptables -A SB_FORWARD -i "$UPLINK_IFACE" -o "$AP_IFACE" -m state --state RELATED,ESTABLISHED -j ACCEPT
iptables -A SB_FORWARD -i "$AP_IFACE" -o "$UPLINK_IFACE" -j ACCEPT
iptables -A SB_FORWARD -j RETURN

# NAT table chain
iptables -t nat -N SB_POSTROUTING 2>/dev/null || true
iptables -t nat -F SB_POSTROUTING
if ! iptables -t nat -C POSTROUTING -j SB_POSTROUTING 2>/dev/null; then
  iptables -t nat -I POSTROUTING 1 -j SB_POSTROUTING
fi
iptables -t nat -A SB_POSTROUTING -o "$UPLINK_IFACE" -j MASQUERADE
iptables -t nat -A SB_POSTROUTING -j RETURN

# Start services
echo "[*] Starting dnsmasq + hostapd"
systemctl unmask hostapd >/dev/null 2>&1 || true
systemctl enable dnsmasq hostapd >/dev/null 2>&1 || true
systemctl restart dnsmasq
systemctl restart hostapd

echo
echo "[+] AP should be up."
echo "    SSID: $SSID"
echo "    AP IP: $AP_ADDR"
echo
echo "Next: start capture with:"
echo "    sudo AP_IFACE=$AP_IFACE bash scripts/capture.sh start"
