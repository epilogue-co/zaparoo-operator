#!/bin/bash
# Epilogue Operator for MiSTer — installer & manager.
#
# Bridges an Epilogue Operator (USB cartridge reader) to Zaparoo: insert a
# cartridge and the matching FPGA core launches automatically; remove it to
# return to the menu. Run this from the MiSTer Scripts menu (F12 -> Scripts).

# Paths are overridable via environment so Operator_test.sh can point them at
# a temp dir; defaults are the real MiSTer locations.
OPDIR="${OPDIR:-/media/fat/Scripts/.operator}"
BIN="${BIN:-$OPDIR/zaparoo-operator}"
LOG="${LOG:-/tmp/zaparoo-operator.log}"
TOKEN="${TOKEN:-/tmp/zaparoo-operator.token}"
STATUS="${STATUS:-/tmp/zaparoo-operator.status}"
STARTUP="${STARTUP:-/media/fat/linux/user-startup.sh}"
ZAPCFG="${ZAPCFG:-/media/fat/zaparoo/config.toml}"
ZAPSH="${ZAPSH:-/media/fat/Scripts/zaparoo.sh}"
BEGIN="#==== Epilogue Operator BEGIN ===="
END="#==== Epilogue Operator END ===="
RUNLINE="[ \"\$1\" != \"stop\" ] && [ -x $BIN ] && $BIN bridge > $LOG 2>&1 &"

is_running()        { pgrep -f "$BIN bridge" >/dev/null 2>&1; }
autostart_enabled() { [ -f "$STARTUP" ] && grep -qF "$BEGIN" "$STARTUP"; }
operator_present()  { "$BIN" detect 2>/dev/null | grep -qi "Operator"; }

# config_ok reports whether the Zaparoo config already has the settings the
# Operator needs: auto_detect off (so libnfc/pn532 don't grab our /dev/ttyACM*),
# hold mode (so removing the cart stops the core), and a [[readers.connect]]
# entry with BOTH driver='file' and a path on our token -- not just a path=
# line anywhere in the file, which could belong to an unrelated entry or
# survive with its driver commented out, silently doing nothing. Matches must
# be on real (non-commented) setting lines, so a commented-out block never
# makes a broken config look ok.
config_ok() {
  [ -f "$ZAPCFG" ] || return 1
  grep -Eq "^[[:space:]]*auto_detect[[:space:]]*=[[:space:]]*false" "$ZAPCFG" || return 1
  grep -Eq "^[[:space:]]*mode[[:space:]]*=[[:space:]]*'?hold'?" "$ZAPCFG" || return 1
  awk -v tok="$TOKEN" '
    /^\[\[readers\.connect\]\]/ { driver=0; path=0 }
    /^[[:space:]]*driver[[:space:]]*=/ { if ($0 ~ /file/) driver=1 }
    /^[[:space:]]*path[[:space:]]*=/ { if (index($0, tok)) path=1 }
    driver && path { found=1 }
    END { exit !found }
  ' "$ZAPCFG" || return 1
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

# with_lock runs its argument while holding a simple mkdir-based mutex on
# $STARTUP, so two concurrent Operator.sh invocations (e.g. a double F12 tap
# on first install, before autostart is enabled) can't race on the same
# read-modify-write cycle: reproduced 5/5 without this, duplicating the
# autostart block (bridge launched twice at boot) or, under heavier
# contention, silently deleting another tool's unrelated autostart line with
# no way to recover it. mkdir is atomic even on MiSTer's filesystem; a stale
# lock left by a killed process is cleared after LOCK_STALE_SECS.
LOCK_STALE_SECS=10
with_lock() {
  local lockdir="$STARTUP.lock" waited=0 now lockedat
  while ! mkdir "$lockdir" 2>/dev/null; do
    if [ -f "$lockdir/acquired" ]; then
      now=$(date +%s)
      lockedat=$(cat "$lockdir/acquired" 2>/dev/null || echo "$now")
      if [ $((now - lockedat)) -gt "$LOCK_STALE_SECS" ]; then
        rm -rf "$lockdir"
        continue
      fi
    fi
    waited=$((waited + 1))
    if [ "$waited" -gt 50 ]; then
      echo "Operator: timed out waiting for the startup-script lock" >&2
      return 1
    fi
    sleep 0.1
  done
  date +%s > "$lockdir/acquired" 2>/dev/null
  "$@"
  local rc=$?
  rm -rf "$lockdir"
  return $rc
}

# Idempotently strip our marker block, then re-append it. Exact-line marker
# match (not substring) so the string appearing inside unrelated content
# elsewhere in the file can't be mistaken for our block. A unique per-call tmp
# name, since with_lock is the only thing making this safe against a
# concurrent run, not the filename itself.
strip_block() {
  [ -f "$STARTUP" ] || return 0
  local tmp
  tmp="$(mktemp "$STARTUP.XXXXXX")" || return 1
  if awk -v b="$BEGIN" -v e="$END" '$0==b{s=1} !s{print} $0==e{s=0}' "$STARTUP" > "$tmp"; then
    mv "$tmp" "$STARTUP"
  else
    rm -f "$tmp"
    return 1
  fi
}
enable_autostart() { with_lock _enable_autostart_locked; }
_enable_autostart_locked() {
  [ -f "$STARTUP" ] || printf '#!/bin/bash\n' > "$STARTUP"
  strip_block
  printf '\n%s\n%s\n%s\n' "$BEGIN" "$RUNLINE" "$END" >> "$STARTUP"
  chmod +x "$STARTUP"
}
disable_autostart() { with_lock strip_block; }

start_bridge() {
  is_running && return 0
  [ -e "$ZAPSH" ] && "$ZAPSH" -service start >/dev/null 2>&1
  "$BIN" bridge > "$LOG" 2>&1 &
}
stop_bridge() { pkill -f "$BIN bridge" 2>/dev/null; sleep 1; }

# uninstall stops the bridge, removes autostart, and restores the original
# Zaparoo config if ensure_config replaced it -- otherwise a user who had
# other readers (NFC, etc.) working before installing Operator is left with
# auto_detect=false and a dead file-reader entry forever, with no path back to
# their working setup. Returns 0 if a config was restored, 1 if there was
# nothing to restore.
uninstall() {
  stop_bridge
  disable_autostart
  if [ -f "$ZAPCFG.pre-operator" ]; then
    mv "$ZAPCFG.pre-operator" "$ZAPCFG"
    return 0
  fi
  return 1
}

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
      8) if uninstall; then
           dialog --msgbox "Bridge stopped, autostart removed, and your original Zaparoo config was restored.\nFiles kept in $OPDIR." 8 60
         else
           dialog --msgbox "Bridge stopped and autostart removed.\nFiles kept in $OPDIR." 7 56
         fi ;;
    esac
  done
  clear
}

# Guarded so Operator_test.sh can source this file for its functions without
# running the installer.
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
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
fi
