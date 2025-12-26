#!/usr/bin/env bash
set -euo pipefail

PCAP="${1:-}"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPORTS="$REPO_ROOT/reports"
mkdir -p "$REPORTS"

if [[ -z "$PCAP" ]]; then
  echo "Usage: $0 <path/to.pcap>"
  echo "Tip:  $0 captures/latest.pcap"
  exit 1
fi

if [[ ! -f "$PCAP" ]]; then
  echo "PCAP not found: $PCAP"
  exit 1
fi

if ! command -v tshark >/dev/null 2>&1; then
  echo "tshark not found. Install: sudo apt install tshark"
  exit 1
fi

echo "[*] Collecting artifacts from: $PCAP"
BASE="$(basename "$PCAP" .pcap)"
OUTDIR="$REPORTS/$BASE"
mkdir -p "$OUTDIR"

# DNS queries
echo "[*] Extracting DNS queries..."
tshark -r "$PCAP" -Y "dns.qry.name" \
  -T fields -E header=y -E separator=, -E quote=d -E occurrence=f \
  -e frame.time_epoch -e ip.src -e dns.qry.name -e dns.qry.type \
  > "$OUTDIR/dns_queries.csv" || true

# TLS SNI + ALPN
echo "[*] Extracting TLS SNI + ALPN..."
tshark -r "$PCAP" -Y "tls.handshake.extensions_server_name" \
  -T fields -E header=y -E separator=, -E quote=d -E occurrence=f \
  -e frame.time_epoch -e ip.src -e tls.handshake.extensions_server_name -e tls.handshake.extensions_alpn_str \
  > "$OUTDIR/tls_sni.csv" || true

# HTTP requests (if any)
echo "[*] Extracting HTTP requests (if any)..."
tshark -r "$PCAP" -Y "http.request" \
  -T fields -E header=y -E separator=, -E quote=d -E occurrence=f \
  -e frame.time_epoch -e ip.src -e http.request_method -e http.host -e http.request_uri -e http.user_agent \
  > "$OUTDIR/http_requests.csv" || true

# QUIC/HTTP3 hint (UDP 443)
echo "[*] Extracting UDP/443 rows (QUIC hint)..."
tshark -r "$PCAP" -Y "udp.port==443" \
  -T fields -E header=y -E separator=, -E quote=d -E occurrence=f \
  -e frame.time_epoch -e ip.src -e ip.dst -e udp.length \
  > "$OUTDIR/udp_443.csv" || true

# Endpoint conversations (summaries)
echo "[*] Writing tcp/udp conversation summaries..."
tshark -r "$PCAP" -q -z conv,tcp > "$OUTDIR/conv_tcp.txt" || true
tshark -r "$PCAP" -q -z conv,udp > "$OUTDIR/conv_udp.txt" || true

# Small JSON metadata
echo "[*] Writing metadata..."
python3 - <<'PY' "$PCAP" "$OUTDIR/meta.json"
import json, os, sys, time, hashlib
pcap = sys.argv[1]
out = sys.argv[2]
st = os.stat(pcap)
meta = {
  "pcap_path": os.path.abspath(pcap),
  "pcap_size_bytes": st.st_size,
  "pcap_mtime_epoch": int(st.st_mtime),
}
h = hashlib.sha256()
with open(pcap, "rb") as f:
  for chunk in iter(lambda: f.read(1024*1024), b""):
    h.update(chunk)
meta["pcap_sha256"] = h.hexdigest()
with open(out, "w") as f:
  json.dump(meta, f, indent=2)
print("wrote", out)
PY

echo
echo "[+] Done."
echo "    Outputs: $OUTDIR"
echo "Next:"
echo "    . .venv/bin/activate"
echo "    python analysis/analyze_capture.py --input $OUTDIR --out $OUTDIR/summary.md"
