#!/usr/bin/env bash
# Single script to capture traffic, collect artifacts, and generate summary
# Usage: sudo bash scripts/capture_and_analyze.sh [duration_seconds]
#
# If duration is provided, captures for that many seconds then stops.
# If no duration, waits for user to press Enter to stop.

set -euo pipefail

DURATION="${1:-}"
AP_IFACE="${AP_IFACE:-wlx00c0cab9645b}"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VENV="$REPO_ROOT/.venv"

die() { echo "[FATAL] $*" >&2; exit 1; }
info() { echo "[*] $*"; }
ok() { echo "[+] $*"; }

[[ "${EUID}" -eq 0 ]] || die "Run with sudo"
[[ -d "$VENV" ]] || die "Python venv not found at $VENV - run install_ubuntu22.sh first"

# Start capture
info "Starting capture on $AP_IFACE..."
bash "$REPO_ROOT/scripts/capture.sh" start

if [[ -n "$DURATION" ]]; then
  info "Capturing for $DURATION seconds..."
  sleep "$DURATION"
else
  echo ""
  echo "========================================"
  echo "CAPTURE RUNNING"
  echo "========================================"
  echo ""
  echo "Now trigger activity on the device."
  echo "Press ENTER when done to stop capture."
  echo ""
  read -r
fi

# Stop capture
info "Stopping capture..."
bash "$REPO_ROOT/scripts/capture.sh" stop

# Find the latest capture
LATEST="$REPO_ROOT/captures/latest.pcap"
if [[ ! -L "$LATEST" ]] && [[ ! -f "$LATEST" ]]; then
  die "No capture file found at $LATEST"
fi

PCAP_FILE=$(readlink -f "$LATEST")
info "Processing: $PCAP_FILE"

# Collect artifacts
info "Extracting artifacts..."
bash "$REPO_ROOT/scripts/collect.sh" "$PCAP_FILE"

# Find the report directory
PCAP_BASE=$(basename "$PCAP_FILE" .pcap)
REPORT_DIR="$REPO_ROOT/reports/$PCAP_BASE"

if [[ ! -d "$REPORT_DIR" ]]; then
  die "Report directory not found: $REPORT_DIR"
fi

# Run analysis
info "Generating summary..."
source "$VENV/bin/activate"
python "$REPO_ROOT/analysis/analyze_capture.py" --input "$REPORT_DIR" --out "$REPORT_DIR/summary.md"

# Output
echo ""
echo "========================================"
ok "CAPTURE COMPLETE"
echo "========================================"
echo ""
echo "PCAP: $PCAP_FILE"
echo "Report: $REPORT_DIR"
echo ""
echo "--- SUMMARY ---"
echo ""
cat "$REPORT_DIR/summary.md"
