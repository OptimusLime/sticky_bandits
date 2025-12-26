#!/usr/bin/env bash
set -euo pipefail

if [[ "${EUID}" -ne 0 ]]; then
  echo "Please run as root (sudo) so we can install packages."
  exit 1
fi

echo "[*] Updating apt..."
apt update

echo "[*] Installing system packages..."
# hostapd + dnsmasq: Wi-Fi AP + DHCP/DNS
# iptables-persistent: save/restore rules; we also maintain a dedicated chain
# tcpdump + tshark: packet capture + extraction
# jq: convenience for parsing / scripting
# python3-venv: local venv for analysis scripts
DEBIAN_FRONTEND=noninteractive apt install -y \
  hostapd dnsmasq iptables iptables-persistent \
  tcpdump tshark jq \
  python3 python3-venv python3-pip

echo "[*] Ensuring hostapd is unmasked (Ubuntu sometimes masks it)..."
systemctl unmask hostapd >/dev/null 2>&1 || true

echo "[*] Creating Python venv at .venv ..."
cd "$(dirname "$0")/.."
python3 -m venv .venv
# shellcheck disable=SC1091
source .venv/bin/activate
pip install -U pip wheel
pip install -r analysis/requirements.txt

cat <<'EOF'

Done.

Next:
  1) Identify interfaces:
       ip link
  2) Bring up AP:
       sudo AP_IFACE=wlan0 UPLINK_IFACE=eth0 SSID="sticky_bandits" PASSPHRASE="..." bash scripts/ap_up.sh
  3) Capture:
       sudo AP_IFACE=wlan0 bash scripts/capture.sh start

EOF
