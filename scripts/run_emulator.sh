#!/bin/bash
# Default emulator workflow: boot the Pixel_Tyres AVD and run BOTH Flutter
# apps in debug mode (hot reload enabled) inside a tmux session.
#
#   make emulator          # or: scripts/run_emulator.sh
#
# Once running: press r in a pane to hot reload, R to hot restart, q to quit.
set -euo pipefail

AVD="${AVD:-Pixel_Tyres}"
SESSION="shiraztyres"
APP_DRIVER="$(cd "$(dirname "$0")/../mobile" && pwd)"
APP_CUSTOMER="$(cd "$(dirname "$0")/../mobile_customer" && pwd)"
EMULATOR_BIN="${ANDROID_SDK_ROOT:-$HOME/Android/Sdk}/emulator/emulator"
ADB="${ANDROID_SDK_ROOT:-$HOME/Android/Sdk}/platform-tools/adb"

boot_emulator() {
  # Reuse an already-running booted emulator, else start one.
  if "$ADB" -s emulator-5554 get-state >/dev/null 2>&1; then
    local booted
    booted=$("$ADB" -s emulator-5554 shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')
    if [ "$booted" = "1" ]; then
      echo "Emulator already running (emulator-5554)."
      return 0
    fi
  fi
  echo "Starting $AVD ..."
  nohup "$EMULATOR_BIN" -avd "$AVD" -no-snapshot-load -no-snapshot-save -no-boot-anim >/tmp/shiraztyres_emu.log 2>&1 &
  "$ADB" wait-for-device
  until [ "$("$ADB" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" = "1" ]; do
    sleep 3
  done
  echo "Emulator booted."
}

boot_emulator

# Start flutter run for both apps in tmux panes; debug builds enable hot reload.
tmux kill-session -t "$SESSION" >/dev/null 2>&1 || true
tmux new-session -d -s "$SESSION" -x 200 -y 50
tmux send-keys -t "$SESSION" "cd $APP_DRIVER && flutter run -d emulator-5554" Enter
tmux split-window -h -t "$SESSION"
tmux send-keys -t "$SESSION" "cd $APP_CUSTOMER && flutter run -d emulator-5554" Enter
tmux select-pane -L -t "$SESSION"

echo "Both apps launching in tmux session '$SESSION' (left: driver, right: customer)."
echo "Attach with: tmux attach -t $SESSION   |   r = hot reload, R = hot restart, q = quit"