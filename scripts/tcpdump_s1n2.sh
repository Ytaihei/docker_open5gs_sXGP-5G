#!/bin/bash
# tcpdump wrapper for br-sXGP-5G network (S1-N2 converter path)
# Usage:
#   ./scripts/tcpdump_s1n2.sh start   # start capture in background
#   ./scripts/tcpdump_s1n2.sh stop    # stop capture if running
#   ./scripts/tcpdump_s1n2.sh status  # show status
#
# Captures:
# - S1AP over SCTP (port 36412)
# - GTP-U on N3 for local endpoint (host 172.24.0.30 by default)

set -euo pipefail

NETWORK_BR="br-sXGP-5G"
LOG_DIR="$(cd "$(dirname "$0")"/.. && pwd)/log"
PID_FILE="/tmp/tcpdump_s1n2.pid"
NOHUP_OUT="/tmp/tcpdump_s1n2.nohup"
LOCAL_N3_IP="172.24.0.30"

ensure_iface() {
  if ! ip link show "$NETWORK_BR" >/dev/null 2>&1; then
    echo "Error: interface '$NETWORK_BR' not found. Is the sXGP-5G stack up?" >&2
    exit 1
  fi
}

start_capture() {
  ensure_iface
  mkdir -p "$LOG_DIR"
  ts=$(date +%Y%m%d_%H%M%S)
  pcap="$LOG_DIR/${ts}_ics_s1ap.pcap"
  echo "Starting capture on $NETWORK_BR -> $pcap"
  # shellcheck disable=SC2086
  nohup tcpdump -i "$NETWORK_BR" -nn -s 0 -w "$pcap" \
    "sctp port 36412 or (udp port 2152 and host $LOCAL_N3_IP)" \
    >"$NOHUP_OUT" 2>&1 &
  echo $! >"$PID_FILE"
  sleep 0.3
  head -n 1 "$NOHUP_OUT" || true
}

stop_capture() {
  if [[ -f "$PID_FILE" ]]; then
    pid=$(cat "$PID_FILE" || true)
    if [[ -n "${pid}" ]] && kill -0 "$pid" 2>/dev/null; then
      kill "$pid" || true
      wait "$pid" 2>/dev/null || true
      echo "Stopped capture (pid=$pid)"
      rm -f "$PID_FILE"
    else
      echo "No running tcpdump found (stale pidfile?)"
      rm -f "$PID_FILE"
    fi
  else
    echo "No pidfile present; nothing to stop"
  fi
}

status_capture() {
  if [[ -f "$PID_FILE" ]]; then
    pid=$(cat "$PID_FILE" || true)
    if [[ -n "${pid}" ]] && kill -0 "$pid" 2>/dev/null; then
      echo "Running (pid=$pid)"
      tr -d '\0' < "/proc/$pid/cmdline" 2>/dev/null || true
      echo
      exit 0
    fi
  fi
  echo "Not running"
}

case "${1:-}" in
  start) start_capture ;;
  stop) stop_capture ;;
  status) status_capture ;;
  *) echo "Usage: $0 {start|stop|status}" >&2; exit 2 ;;
esac
