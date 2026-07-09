#!/bin/bash
# Epilogue Operator for MiSTer — installer & manager.
#
# Bridges an Epilogue Operator (USB cartridge reader) to Zaparoo: insert a
# cartridge and the matching FPGA core launches automatically; remove it to
# return to the menu. Run this from the MiSTer Scripts menu (F12 -> Scripts).

OPDIR="/media/fat/Scripts/.operator"
BIN="$OPDIR/zaparoo-operator"
LOG="/tmp/zaparoo-operator.log"
TOKEN="/tmp/zaparoo-operator.token"
STATUS="/tmp/zaparoo-operator.status"
STARTUP="/media/fat/linux/user-startup.sh"
ZAPCFG="/media/fat/zaparoo/config.toml"
ZAPSH="/media/fat/Scripts/zaparoo.sh"
BEGIN="#==== Epilogue Operator BEGIN ===="
END="#==== Epilogue Operator END ===="
RUNLINE="[ \"\$1\" != \"stop\" ] && [ -x $BIN ] && $BIN bridge > $LOG 2>&1 &"

is_running()        { pgrep -f "$BIN bridge" >/dev/null 2>&1; }
autostart_enabled() { [ -f "$STARTUP" ] && grep -qF "$BEGIN" "$STARTUP"; }
operator_present()  { "$BIN" detect 2>/dev/null | grep -qi "Operator"; }

# config_ok reports whether the Zaparoo config already has the three settings the
# Operator needs: auto_detect off (so libnfc/pn532 don't grab our /dev/ttyACM*),
# hold mode (so removing the cart stops the core), and a file reader on our token.
# Matches must be on real (non-commented) setting lines, so a commented-out block
# never makes a broken config look ok.
config_ok() {
  [ -f "$ZAPCFG" ] || return 1
  grep -Eq "^[[:space:]]*auto_detect[[:space:]]*=[[:space:]]*false" "$ZAPCFG" || return 1
  grep -Eq "^[[:space:]]*mode[[:space:]]*=[[:space:]]*'?hold'?" "$ZAPCFG" || return 1
  # token must be on a real (non-commented) path = ... line
  grep -E "^[[:space:]]*path[[:space:]]*=" "$ZAPCFG" | grep -qF "$TOKEN" || return 1
  return 0
}

write_config() {
  mkdir -p "$(dirname "$ZAPCFG")"
  cat > "$ZAPCFG" <<EOF
[readers]
auto_detect = false

[readers.scan]
mode = 'hold'
exit_delay = 1.0

[[readers.connect]]
driver = 'file'
path = '$TOKEN'
EOF
}

# ensure_config guarantees the required settings are present. The old version
# skipped when ANY config existed, so an existing Zaparoo user silently never got
# auto_detect=false and nothing launched. Now: if the settings are missing we back
# up the existing config and write ours (the user can re-add other readers from
# the backup).
CONFIG_REPLACED=0
ensure_config() {
  config_ok && return 0
  if [ -f "$ZAPCFG" ]; then
    # Keep the FIRST backup (the user's original); don't clobber it on a later run.
    [ -f "$ZAPCFG.pre-operator" ] || cp -p "$ZAPCFG" "$ZAPCFG.pre-operator" 2>/dev/null
    CONFIG_REPLACED=1
    echo "Operator: replaced Zaparoo config (backup at $ZAPCFG.pre-operator)" >&2
  fi
  write_config
}

# notify_config_replaced shows the user, on screen, that we replaced their config
# (so an existing Zaparoo user knows to re-add their other readers).
notify_config_replaced() {
  [ "$CONFIG_REPLACED" = "1" ] || return 0
  if command -v dialog >/dev/null 2>&1 && [ -t 1 ]; then
    dialog --title "Zaparoo config updated" --msgbox \
      "Your Zaparoo config didn't have the Operator settings, so it was replaced.\n\nA backup is at:\n$ZAPCFG.pre-operator\n\nIf you had other readers (NFC, etc.), re-add them from the backup." 12 64
  fi
}

# Idempotently strip our marker block, then re-append it.
strip_block() {
  [ -f "$STARTUP" ] || return 0
  awk -v b="$BEGIN" -v e="$END" 'index($0,b){s=1} !s{print} index($0,e){s=0}' \
    "$STARTUP" > "$STARTUP.tmp" && mv "$STARTUP.tmp" "$STARTUP"
}
enable_autostart() {
  [ -f "$STARTUP" ] || printf '#!/bin/bash\n' > "$STARTUP"
  strip_block
  printf '\n%s\n%s\n%s\n' "$BEGIN" "$RUNLINE" "$END" >> "$STARTUP"
  chmod +x "$STARTUP"
}
disable_autostart() { strip_block; }

start_bridge() {
  is_running && return 0
  [ -e "$ZAPSH" ] && "$ZAPSH" -service start >/dev/null 2>&1
  "$BIN" bridge > "$LOG" 2>&1 &
}
stop_bridge() { pkill -f "$BIN bridge" 2>/dev/null; sleep 1; }

status_text() {
  local r a o now
  is_running && r="running" || r="stopped"
  autostart_enabled && a="enabled" || a="disabled"
  operator_present && o="connected" || o="not detected"
  now="idle"
  [ -s "$STATUS" ] && now="$(cat "$STATUS")"
  printf "Bridge:    %s\nAutostart: %s\nOperator:  %s\nNow:       %s\n\nInsert your Operator with a cartridge to play;\nremove the cartridge to return to the menu." "$r" "$a" "$o" "$now"
}

menu() {
  while true; do
    local c
    c=$(dialog --clear --stdout --title " Epilogue Operator " \
      --cancel-label "Exit" \
      --menu "$(status_text)" 21 64 8 \
      1 "Start bridge" \
      2 "Stop bridge" \
      3 "Restart bridge" \
      4 "Enable autostart on boot" \
      5 "Disable autostart" \
      6 "Watch activity (live)" \
      7 "View log" \
      8 "Uninstall (keeps files)") || break
    case "$c" in
      1) start_bridge ;;
      2) stop_bridge ;;
      3) stop_bridge; start_bridge ;;
      4) ensure_config; enable_autostart; dialog --msgbox "Autostart enabled — the bridge starts on boot." 6 56 ;;
      5) disable_autostart; dialog --msgbox "Autostart disabled." 6 40 ;;
      6) touch "$LOG"; dialog --title "Live — insert a cartridge to watch it read (Exit to return)" --tailbox "$LOG" 22 78 ;;
      7) [ -s "$LOG" ] && dialog --title "Log" --textbox "$LOG" 20 72 || dialog --msgbox "No log yet." 6 30 ;;
      8) stop_bridge; disable_autostart; dialog --msgbox "Bridge stopped and autostart removed.\nFiles kept in $OPDIR." 7 56 ;;
    esac
  done
  clear
}

if [ ! -x "$BIN" ]; then
  echo "ERROR: $BIN not found. Reinstall the Operator bridge." >&2
  sleep 3; exit 1
fi

# First run sets everything up; thereafter it (re)confirms and shows the menu.
ensure_config
notify_config_replaced
autostart_enabled || enable_autostart
start_bridge

if command -v dialog >/dev/null 2>&1 && [ -t 1 ]; then
  menu
else
  clear; echo "Epilogue Operator bridge"; echo; status_text; echo; echo "Log: $LOG"; sleep 4
fi
