#!/usr/bin/env bash
set -euo pipefail

CMD="${1:-}"
AP_IFACE="${AP_IFACE:-wlx00c0cab9645b}"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CAP_DIR="$REPO_ROOT/captures"
STATE_DIR="$REPO_ROOT/.state"
PID_FILE="$STATE_DIR/capture.pid"
LATEST_LINK="$CAP_DIR/latest.pcap"

mkdir -p "$CAP_DIR" "$STATE_DIR"

need_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    echo "Run with sudo/root (packet capture)."
    exit 1
  fi
}

start_capture() {
  need_root
  if [[ -f "$PID_FILE" ]]; then
    if kill -0 "$(cat "$PID_FILE")" >/dev/null 2>&1; then
      echo "[!] Capture already running (pid $(cat "$PID_FILE"))."
      exit 1
    fi
  fi

  TS="$(date +"%Y%m%d_%H%M%S")"
  OUT="$CAP_DIR/capture_${TS}.pcap"
  echo "[*] Starting tcpdump on $AP_IFACE -> $OUT"
  tcpdump -i "$AP_IFACE" -s0 -n -w "$OUT" >/dev/null 2>&1 &
  PID=$!
  echo "$PID" > "$PID_FILE"
  ln -sf "$(basename "$OUT")" "$LATEST_LINK"
  echo "[+] PID=$PID"
}

stop_capture() {
  need_root
  if [[ ! -f "$PID_FILE" ]]; then
    echo "[*] No capture pid file found."
    exit 0
  fi
  PID="$(cat "$PID_FILE")"
  if kill -0 "$PID" >/dev/null 2>&1; then
    echo "[*] Stopping capture pid=$PID"
    kill "$PID"
    sleep 0.5
    # ensure gone
    kill -9 "$PID" >/dev/null 2>&1 || true
  else
    echo "[*] PID file exists but process not running (pid=$PID)."
  fi
  rm -f "$PID_FILE"
  echo "[+] Stopped."
}

status_capture() {
  if [[ -f "$PID_FILE" ]] && kill -0 "$(cat "$PID_FILE")" >/dev/null 2>&1; then
    echo "running pid=$(cat "$PID_FILE")"
  else
    echo "stopped"
  fi
  if [[ -L "$LATEST_LINK" ]]; then
    echo "latest=$(readlink "$LATEST_LINK")"
  fi
}

case "$CMD" in
  start) start_capture ;;
  stop) stop_capture ;;
  status) status_capture ;;
  *)
    echo "Usage: $0 {start|stop|status}"
    exit 1
    ;;
esac
