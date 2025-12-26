# sticky_bandits

A small toolkit to run an Ubuntu 22.04 box as a **Wi‑Fi access point + gateway** for a device you own, so you can **capture and analyze** its network behavior (DNS, TLS SNI, HTTP if present, traffic patterns). This repo is designed to help you understand request/response structure *when feasible* and to build a future API-compatibility shim.

> ⚠️ Notes & boundaries
>
> - This is intended for **your own devices** / environments you control and have permission to test.
> - If the device uses **HTTPS with proper certificate validation** (common), passive capture won’t reveal HTTP headers/bodies.
> - This repo does **not** include techniques to bypass TLS protections (pinning, mTLS, etc.). It focuses on lawful, cooperative, and observable routes.

## Repo layout

- `scripts/install_ubuntu22.sh` — installs system dependencies (hostapd/dnsmasq/tcpdump/tshark/etc.) + creates a Python venv.
- `scripts/ap_up.sh` — configures and starts the AP/gateway services (hostapd + dnsmasq + NAT).
- `scripts/capture.sh` — starts/stops capture to `captures/` and records a PID in `.state/`.
- `scripts/collect.sh` — extracts structured artifacts from a `.pcap` into `reports/`.
- `analysis/analyze_capture.py` — summarizes the extracted artifacts into a markdown report.
- `docs/ASSISTANT_CONTEXT.md` — context for AI assistants and the longer-term plan.

## Quickstart (SSH / headless)

### 0) Clone + install
```bash
git clone <your_repo_url> sticky_bandits
cd sticky_bandits
bash scripts/install_ubuntu22.sh
```

### 1) Bring up the Wi‑Fi AP
Pick interfaces:
- **AP interface**: your Wi‑Fi card in AP mode (often `wlan0` or `wlp…`)
- **Uplink interface**: your internet-facing interface (often `eth0`)

```bash
sudo AP_IFACE=wlan0 UPLINK_IFACE=eth0 \
  SSID="sticky_bandits" PASSPHRASE="change-me-now-please" \
  bash scripts/ap_up.sh
```

### 2) Start capture
```bash
sudo AP_IFACE=wlan0 bash scripts/capture.sh start
```

Trigger the device behavior (image generation), then stop:

```bash
sudo bash scripts/capture.sh stop
```

### 3) Collect artifacts + analyze
```bash
bash scripts/collect.sh captures/latest.pcap
. .venv/bin/activate
python analysis/analyze_capture.py --input reports --out reports/summary.md
```

Open `reports/summary.md`.

## Common troubleshooting

### AP doesn’t start
Check:
```bash
sudo systemctl status hostapd
sudo journalctl -u hostapd --no-pager -n 200
```

### Device connects but no internet
Check NAT + forwarding:
```bash
sysctl net.ipv4.ip_forward
sudo iptables -t nat -S | sed -n '1,120p'
sudo iptables -S | sed -n '1,160p'
```

### I only see encrypted TLS
That’s normal. Look at:
- DNS queries (what domains?)
- TLS SNI (what hostnames?)
- whether traffic is TCP/443 vs UDP/443 (QUIC/HTTP3)
- polling patterns, CDN downloads, payload sizes

## Safety / permissions
Use only on networks/devices you own or have explicit authorization to test.
