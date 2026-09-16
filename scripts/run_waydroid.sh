#!/bin/bash
# Waydroid workflow: connect adb to the running Waydroid container and run BOTH
# Flutter apps in debug mode (hot reload enabled) inside a tmux session.
#
#   make waydroid          # or: scripts/run_waydroid.sh
#
# Waydroid is not the AVD emulator: it is a LXC container on the waydroid0
# bridge, so the host is reachable at the bridge gateway (192.168.240.1), not at
# the emulator's 10.0.2.2. The apps default to 10.0.2.2 on Android, hence the
# explicit --dart-define here.
set -euo pipefail

APP_DRIVER="$(cd "$(dirname "$0")/../mobile" && pwd)"
APP_CUSTOMER="$(cd "$(dirname "$0")/../mobile_customer" && pwd)"
SESSION="shiraztyres"

HOST_IP="${HOST_IP:-$(ip -4 -br addr show waydroid0 | awk '{print $3}' | cut -d/ -f1)}"
[ -n "$HOST_IP" ] || { echo "waydroid0 has no address — is the container running?" >&2; exit 1; }

DEVICE_IP="${DEVICE_IP:-$(waydroid status | awk -F'\t' '/IP address/ {print $NF}' | tr -d ' ')}"
[ -n "$DEVICE_IP" ] || { echo "Could not read the Waydroid IP from 'waydroid status'." >&2; exit 1; }

DEVICE="$DEVICE_IP:5555"
adb connect "$DEVICE" >/dev/null
adb -s "$DEVICE" wait-for-device

DEFINES="--dart-define=API_BASE_URL=http://$HOST_IP:8000/api/v1 --dart-define=WS_BASE_URL=ws://$HOST_IP:8000/ws"

tmux kill-session -t "$SESSION" >/dev/null 2>&1 || true
tmux new-session -d -s "$SESSION" -x 200 -y 50
tmux send-keys -t "$SESSION" "cd $APP_DRIVER && flutter run -d $DEVICE $DEFINES" Enter
tmux split-window -h -t "$SESSION"
tmux send-keys -t "$SESSION" "cd $APP_CUSTOMER && flutter run -d $DEVICE $DEFINES" Enter
tmux select-pane -L -t "$SESSION"

echo "Both apps launching against http://$HOST_IP:8000 on $DEVICE (left: driver, right: customer)."
echo "Attach with: tmux attach -t $SESSION   |   r = hot reload, R = hot restart, q = quit"
