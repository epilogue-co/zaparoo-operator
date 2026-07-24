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
LOCK="${LOCK:-/tmp/zaparoo-operator.lock}"
STARTUP="${STARTUP:-/media/fat/linux/user-startup.sh}"
ZAPCFG="${ZAPCFG:-/media/fat/zaparoo/config.toml}"
ZAPSH="${ZAPSH:-/media/fat/Scripts/zaparoo.sh}"
SCRIPTS="${SCRIPTS:-/media/fat/Scripts}"
MISTERINI="${MISTERINI:-/media/fat/MiSTer.ini}"
CMDIR="${CMDIR:-/media/fat/ConsoleMode}"
RRDIR="${RRDIR:-/media/fat/Scripts/.config/Retroremake}"
NFC_SYS="${NFC_SYS:-/sys/class/tty}"
NFC_BYPATH="${NFC_BYPATH:-/dev/serial/by-path}"
NFC_DEV_PREFIX="${NFC_DEV_PREFIX:-/dev/}"
BEGIN="#==== Epilogue Operator BEGIN ===="
END="#==== Epilogue Operator END ===="
# The autostart block starts the Zaparoo service before the bridge: the
# SuperStation One ships Zaparoo preinstalled but with NO user-startup.sh at
# all, so nothing else starts the service at boot and the bridge would write
# launch tokens nobody reads. `-service start` no-ops when the service is
# already running, so this is safe alongside Zaparoo's own or Console Mode's
# startup line.
ZAPLINE="[ \"\$1\" != \"stop\" ] && [ -e $ZAPSH ] && $ZAPSH -service start >/dev/null 2>&1"
RUNLINE="[ \"\$1\" != \"stop\" ] && [ -x $BIN ] && $BIN bridge > $LOG 2>&1 &"

# is_running reads the PID the daemon itself records in $LOCK (its
# single-instance flock file, held for its whole lifetime) and checks
# /proc/<pid> -- not pgrep, which some MiSTer-family busybox builds compile
# out entirely (CONFIG_PGREP/CONFIG_PKILL unset, leaving only pidof). On such
# a build `pgrep -f ...` used to fail with "not found" under the >/dev/null
# guard, so is_running() silently reported "stopped" no matter what -- which
# also broke start_bridge()'s idempotency check below, letting autostart and
# every later menu visit each launch a new bridge process. /proc and kill are
# always present, so this has no such gap.
running_pid() { [ -s "$LOCK" ] && cat "$LOCK" 2>/dev/null; }
is_running()  { local pid; pid="$(running_pid)"; [ -n "$pid" ] && [ -d "/proc/$pid" ]; }
autostart_enabled() { [ -f "$STARTUP" ] && grep -qF "$BEGIN" "$STARTUP"; }
operator_present()  { "$BIN" detect 2>/dev/null | grep -qi "Operator"; }

# is_superstation heuristically detects a SuperStation One install. The SSO
# matters because it ships with a built-in NFC reader that stock Zaparoo finds
# via auto_detect -- which we turn off -- so on an SSO we must pin that reader
# with an explicit config entry or installing the Operator silently kills the
# console's headline feature. Markers, any of which is enough: the factory
# MiSTer.ini stages Console Mode as the main binary, a Console Mode install
# dir, Retro Remake's forked-downloader config dir, or the pair of factory
# scripts the SSO image ships together. Heuristic by design; a false negative
# just means the user re-runs this script after we refine detection, a false
# positive only adds a reader entry for hardware that isn't there.
is_superstation() {
  grep -qi "ConsoleMode" "$MISTERINI" 2>/dev/null && return 0
  [ -d "$CMDIR" ] && return 0
  [ -d "$RRDIR" ] && return 0
  [ -f "$SCRIPTS/rtc.sh" ] && [ -f "$SCRIPTS/fast_USB_polling_on.sh" ] && return 0
  return 1
}

# internal_nfc_path prints the device path of the SSO's internal NFC bridge: a
# CH340 USB-UART (VID:PID 1a86:7523) on the internal hub. Prefers the
# /dev/serial/by-path symlink -- always created by the stock image's udev, and
# stable because the internal hub port is fixed -- over the raw ttyUSB number,
# which shifts if another USB-serial adapter enumerates first. by-id is NOT
# usable here: CH340s carry no serial number, so every CH340 on the system
# collapses to the same generic by-id name.
internal_nfc_path() {
  local tty dev vid pid link
  for tty in "$NFC_SYS"/ttyUSB*; do
    [ -e "$tty" ] || continue
    vid="$(cat "$tty/device/../idVendor" 2>/dev/null)"
    pid="$(cat "$tty/device/../idProduct" 2>/dev/null)"
    [ "$vid" = "1a86" ] && [ "$pid" = "7523" ] || continue
    dev="$NFC_DEV_PREFIX${tty##*/}"
    for link in "$NFC_BYPATH"/*; do
      [ -e "$link" ] || continue
      if [ "$(readlink -f "$link" 2>/dev/null)" = "$dev" ]; then
        printf '%s\n' "$link"
        return 0
      fi
    done
    printf '%s\n' "$dev"
    return 0
  done
  return 1
}

# sso_nfc prints the internal NFC reader path iff this looks like a
# SuperStation One AND the CH340 bridge is actually present. The two-sided
# gate keeps us from pinning a pn532 entry onto some unrelated CH340 (e.g. a
# tty2oled adapter) on a regular MiSTer, where Zaparoo would then hammer that
# device with PN532 wake probes every second.
sso_nfc() { is_superstation && internal_nfc_path; }

# config_ok reports whether the Zaparoo config already has the settings the
# Operator needs: auto_detect off (so libnfc/pn532 don't grab our /dev/ttyACM*),
# hold mode (so removing the cart stops the core), and a [[readers.connect]]
# entry with BOTH driver='file' and a path on our token -- not just a path=
# line anywhere in the file, which could belong to an unrelated entry or
# survive with its driver commented out, silently doing nothing. Matches must
# be on real (non-commented) setting lines, so a commented-out block never
# makes a broken config look ok. On a SuperStation One it additionally
# requires a pn532 reader entry, so a config written before SSO support (or
# with the console's built-in reader missing) gets rewritten.
config_ok() {
  [ -f "$ZAPCFG" ] || return 1
  # config_schema is not optional decoration: Zaparoo v2.6.2 (stock on the
  # SuperStation One) refuses to start AT ALL on a config without it ("schema
  # version mismatch: got 0, expecting 1"), which turns a working console into
  # a dead one. Requiring it here also heals configs written by installers
  # that predate this check.
  grep -Eq "^[[:space:]]*config_schema[[:space:]]*=[[:space:]]*1" "$ZAPCFG" || return 1
  # Same zero-struct hazard: without an explicit api_port, v2.6.2 binds the
  # API to a random port, cutting off the Zaparoo app and our -reload.
  grep -Eq "^[[:space:]]*api_port[[:space:]]*=[[:space:]]*7497" "$ZAPCFG" || return 1
  grep -Eq "^[[:space:]]*auto_detect[[:space:]]*=[[:space:]]*false" "$ZAPCFG" || return 1
  grep -Eq "^[[:space:]]*mode[[:space:]]*=[[:space:]]*'?hold'?" "$ZAPCFG" || return 1
  awk -v tok="$TOKEN" '
    /^\[\[readers\.connect\]\]/ { driver=0; path=0 }
    /^[[:space:]]*driver[[:space:]]*=/ { if ($0 ~ /file/) driver=1 }
    /^[[:space:]]*path[[:space:]]*=/ { if (index($0, tok)) path=1 }
    driver && path { found=1 }
    END { exit !found }
  ' "$ZAPCFG" || return 1
  if sso_nfc >/dev/null; then
    grep -Eq "^[[:space:]]*driver[[:space:]]*=[[:space:]]*'?pn532" "$ZAPCFG" || return 1
  fi
  return 0
}

# exit_delay 2.5: rides out reader/contact glitches on Zaparoo's side (the
# community-standard range for flaky readers is 2.3-3.0; the bridge debounces
# the cartridge side itself). The pn532 driver string must be spelled exactly
# 'pn532_uart' (or 'pn532'): the v2.6.2 Core that ships on the SuperStation
# One matches connect drivers verbatim -- underscore normalization only
# arrived in v2.7.0.
#
# Zaparoo v2.6.2 loads config into a ZERO struct -- absent keys become Go zero
# values, not defaults. A config without api_port binds the API to port 0 (a
# random port), severing the phone app, web UI, and our own -reload; a config
# without scan_feedback silences scan sounds. So this template must spell out
# every value whose zero differs from stock behavior, and it carries over the
# user's device_id so app pairings survive the rewrite.
write_config() {
  local nfc dev_id
  nfc="$(sso_nfc)" || nfc=""
  dev_id="$(grep -E "^[[:space:]]*device_id[[:space:]]*=" "$ZAPCFG" 2>/dev/null | head -1)"
  mkdir -p "$(dirname "$ZAPCFG")"
  cat > "$ZAPCFG" <<EOF
config_schema = 1

[service]
api_port = 7497
$dev_id

[readers]
auto_detect = false

[readers.scan]
mode = 'hold'
exit_delay = 2.5

[[readers.connect]]
driver = 'file'
path = '$TOKEN'
EOF
  [ -n "$nfc" ] && cat >> "$ZAPCFG" <<EOF

[[readers.connect]]
driver = 'pn532_uart'
path = '$nfc'
EOF
  cat >> "$ZAPCFG" <<EOF

[audio]
scan_feedback = true
EOF
}

# zap_reload tells a running Zaparoo service to re-read config.toml from disk.
# Required after any on-disk config edit while the service runs: Core keeps
# its config in memory and writes that memory back on any settings change (web
# app toggle, TUI save, boot-time device-id mint), silently reverting our
# edit. `-reload` wraps the settings.reload API and exists back to the v2.6.2
# Core the SuperStation One ships; it fails harmlessly when the service isn't
# running.
zap_reload() {
  [ -e "$ZAPSH" ] && "$ZAPSH" -reload >/dev/null 2>&1
  return 0
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
  zap_reload
}

# Zaparoo Core releases older than v2.9.1 mishandle hold mode in ways that hit
# the bridge directly: a token scanned during the exit-delay window is
# swallowed without launching (so a quick cartridge swap leaves a dead menu),
# and reader I/O glitches can arm spurious exits. The SuperStation One ships
# v2.6.2 in its stock image, and Console Mode's installer can silently
# DOWNGRADE an updated Core back below the fix line -- so this is re-checked
# on every run, not just at install. Warn, don't block: the common flows still
# work, and updating is one Update All run away.
ZAPMINVER="2.9.1"
ZAPVER_OLD=""
zap_version() {
  [ -e "$ZAPSH" ] || return 1
  "$ZAPSH" -version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1
}
version_lt() { # true if dotted version $1 < $2 (numeric per field, so 2.15 > 2.9)
  local a1 a2 a3 b1 b2 b3
  IFS=. read -r a1 a2 a3 <<< "$1"
  IFS=. read -r b1 b2 b3 <<< "$2"
  [ "${a1:-0}" -ne "${b1:-0}" ] && { [ "${a1:-0}" -lt "${b1:-0}" ]; return; }
  [ "${a2:-0}" -ne "${b2:-0}" ] && { [ "${a2:-0}" -lt "${b2:-0}" ]; return; }
  [ "${a3:-0}" -lt "${b3:-0}" ]
}
check_zap_version() {
  local v
  v="$(zap_version)" || return 0
  [ -n "$v" ] || return 0
  version_lt "$v" "$ZAPMINVER" && ZAPVER_OLD="$v"
  return 0
}
notify_old_zaparoo() {
  [ -n "$ZAPVER_OLD" ] || return 0
  if command -v dialog >/dev/null 2>&1 && [ -t 1 ]; then
    # Name the exact enable step: Update All skips Zaparoo unless its database
    # is switched on in the settings screen, which is the #1 reason a "zaparoo
    # update" changes nothing and this warning comes back.
    dialog --title "Zaparoo update recommended" --msgbox \
      "Zaparoo Core v$ZAPVER_OLD is installed; v$ZAPMINVER or newer is needed for reliable cartridge launches.\n\nTo update: run update_all, press UP during the countdown, enable 'Zaparoo' under Tools & Scripts, save and update.\n(Update All skips Zaparoo unless enabled there; Console Mode updates can put an old version back.)\n\nOr copy zaparoo.sh from the zaparoo-mister_arm zip at zaparoo.org over /media/fat/Scripts/ and reboot." 15 68
  fi
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
  printf '\n%s\n%s\n%s\n%s\n' "$BEGIN" "$ZAPLINE" "$RUNLINE" "$END" >> "$STARTUP"
  chmod +x "$STARTUP"
}
disable_autostart() { with_lock strip_block; }

start_bridge() {
  is_running && return 0
  [ -e "$ZAPSH" ] && "$ZAPSH" -service start >/dev/null 2>&1
  "$BIN" bridge > "$LOG" 2>&1 &
}

# stop_bridge signals the daemon and waits for it to actually exit (up to
# STOP_WAIT_SECS) instead of a blind sleep -- Run() does a final save flush
# on shutdown, which can legitimately take longer than a fixed guess, and a
# following start_bridge() must not race a lock the old process still holds.
# Falls back to SIGKILL if the daemon doesn't exit in time.
STOP_WAIT_SECS=10
stop_bridge() {
  local pid waited=0
  pid="$(running_pid)"
  [ -n "$pid" ] && [ -d "/proc/$pid" ] || return 0
  kill "$pid" 2>/dev/null
  while [ -d "/proc/$pid" ]; do
    waited=$((waited + 1))
    if [ "$waited" -gt $((STOP_WAIT_SECS * 10)) ]; then
      kill -9 "$pid" 2>/dev/null
      break
    fi
    sleep 0.1
  done
}

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
    zap_reload
    return 0
  fi
  return 1
}

# status_text is what every support screenshot shows, so it must answer the
# questions a photo of this menu otherwise can't: which bridge build is
# installed, which Zaparoo Core version is present, and whether the Zaparoo
# service is actually alive. "Playing X" with the service down/erroring is
# the classic silent failure (bridge writes launch tokens nobody reads) --
# with these lines, one photo of the menu diagnoses it.
bridge_version() {
  local v
  v="$("$BIN" version 2>/dev/null | awk '{print $2}')"
  printf '%s\n' "${v:-?}"
}

# zap_health sums up the other half of the stack in one phrase: Core version
# plus live service state. "ERROR" here (a Core that won't run or a status
# call that errors) is the classic silent failure behind "Playing X" with a
# blank screen -- the bridge writing launch tokens nobody reads.
zap_health() {
  local zv zs
  zv="$(zap_version)"
  if [ -n "$zv" ]; then
    zs="$("$ZAPSH" -service status 2>/dev/null | tail -1)"
    case "$zs" in
      running | stopped) ;;
      *) zs="ERROR" ;;
    esac
    printf 'v%s, service %s\n' "$zv" "$zs"
  elif [ -e "$ZAPSH" ]; then
    echo "ERROR (won't run)"
  else
    echo "not installed"
  fi
}

status_text() {
  local r a o now
  is_running && r="running" || r="stopped"
  autostart_enabled && a="enabled" || a="disabled"
  operator_present && o="connected" || o="not detected"
  now="idle"
  [ -s "$STATUS" ] && now="$(cat "$STATUS")"
  printf "Bridge:    %s (%s)\nAutostart: %s\nOperator:  %s\nZaparoo:   %s\nNow:       %s\n\nInsert your Operator with a cartridge to play;\nremove the cartridge to return to the menu." "$r" "$(bridge_version)" "$a" "$o" "$(zap_health)" "$now"
}

# Zaparoo's own service log; its location has moved between Core versions.
zap_log_path() {
  local p
  for p in /tmp/zaparoo/core.log /media/fat/zaparoo/core.log; do
    [ -f "$p" ] && {
      printf '%s\n' "$p"
      return 0
    }
  done
  return 1
}

# zap_recent_problems condenses the tail of Zaparoo's JSON log into short
# "HH:MM:SS message [detail]" lines -- the actual reason a launch went
# nowhere ("schema version mismatch", "failed to launch", ...) lives there,
# not in the bridge log.
zap_recent_problems() {
  local zl line t msg err
  zl="$(zap_log_path)" || {
    echo "(no zaparoo log found)"
    return 0
  }
  if ! grep -q '"level":"error"' "$zl" 2>/dev/null; then
    echo "(no errors in zaparoo log)"
    return 0
  fi
  grep '"level":"error"' "$zl" | tail -n 4 | while IFS= read -r line; do
    t="$(printf '%s' "$line" | sed -n 's/.*"time":"[^T]*T\([0-9:]\{8\}\).*/\1/p')"
    msg="$(printf '%s' "$line" | sed 's/.*"message":"//;s/".*//')"
    err=""
    case "$line" in
      *'"error":"'*) err=" [$(printf '%s' "$line" | sed 's/.*"error":"//;s/".*//')]" ;;
    esac
    printf '%s %s%s\n' "${t:-??:??:??}" "$msg" "$err"
  done
}

# config_summary compresses the config checks into one line; lowercase means
# present, capitalized NO-* pinpoints what a rewrite would fix.
config_summary() {
  [ -f "$ZAPCFG" ] || {
    echo "config: MISSING"
    return 0
  }
  local s="config:"
  grep -Eq "^[[:space:]]*config_schema[[:space:]]*=[[:space:]]*1" "$ZAPCFG" && s="$s schema" || s="$s NO-SCHEMA"
  grep -Eq "^[[:space:]]*api_port[[:space:]]*=[[:space:]]*7497" "$ZAPCFG" && s="$s api" || s="$s NO-API-PORT"
  grep -Eq "^[[:space:]]*mode[[:space:]]*=[[:space:]]*'?hold'?" "$ZAPCFG" && s="$s hold" || s="$s NO-HOLD"
  grep -Eq "^[[:space:]]*driver[[:space:]]*=[[:space:]]*'?file'?" "$ZAPCFG" && s="$s file" || s="$s NO-FILE-READER"
  grep -Eq "^[[:space:]]*driver[[:space:]]*=[[:space:]]*'?pn532" "$ZAPCFG" && s="$s pn532"
  echo "$s"
}

# snapshot renders the one-screen support view. Testers report by
# photographing the TV -- they cannot copy text -- so the single page must
# carry everything: build + Core health, config state, and the TAILS of both
# logs (a full-log textbox opens at the top, hiding exactly the recent lines
# a photo needs). Everything is pre-wrapped so nothing runs off the edge.
snapshot() {
  local out="$LOG.snap"
  wrap() { if command -v fold >/dev/null 2>&1; then fold -s -w 74; else cat; fi; }
  {
    printf 'Operator %s | Zaparoo %s\n' "$(bridge_version)" "$(zap_health)"
    config_summary
    echo "--- bridge log (latest) ---"
    if [ -s "$LOG" ]; then wrap <"$LOG" | tail -n 9; else echo "(no bridge log yet)"; fi
    echo "--- zaparoo problems (latest) ---"
    zap_recent_problems | wrap | tail -n 5
  } >"$out" 2>/dev/null
  dialog --title " Status snapshot - photograph this screen " --textbox "$out" 22 78
}

menu() {
  while true; do
    local c
    c=$(dialog --clear --stdout --title " Epilogue Operator " \
      --cancel-label "Exit" \
      --menu "$(status_text)" 23 64 9 \
      1 "Start bridge" \
      2 "Stop bridge" \
      3 "Restart bridge" \
      4 "Enable autostart on boot" \
      5 "Disable autostart" \
      6 "Watch activity (live)" \
      7 "Status snapshot (photograph this)" \
      8 "View full log" \
      9 "Uninstall (keeps files)") || break
    case "$c" in
      1) start_bridge ;;
      2) stop_bridge ;;
      3) stop_bridge; start_bridge ;;
      4) ensure_config; enable_autostart; dialog --msgbox "Autostart enabled — the bridge starts on boot." 6 56 ;;
      5) disable_autostart; dialog --msgbox "Autostart disabled." 6 40 ;;
      6) touch "$LOG"; dialog --title "Live — insert a cartridge to watch it read (Exit to return)" --tailbox "$LOG" 22 78 ;;
      7) snapshot ;;
      8) if [ -s "$LOG" ]; then
           # dialog's textbox truncates long lines instead of wrapping, and on
           # error lines the cut-off tail is exactly the part that matters
           # (the field report that motivated this showed "serial read: Por").
           # Pre-wrap into a scratch copy; fold may be missing from a busybox
           # build, in which case the raw log is still shown.
           if command -v fold >/dev/null 2>&1; then
             fold -s -w 74 "$LOG" > "$LOG.view" 2>/dev/null || cp "$LOG" "$LOG.view"
           else
             cp "$LOG" "$LOG.view"
           fi
           dialog --title "Log" --textbox "$LOG.view" 22 78
         else
           dialog --msgbox "No log yet." 6 30
         fi ;;
      9) if uninstall; then
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
  check_zap_version
  notify_old_zaparoo
  # Always re-assert (idempotent): an older install's block predates the
  # Zaparoo service line, and a SuperStation firmware update is a full SD
  # reflash that wipes user-startup.sh entirely -- both self-heal here.
  enable_autostart
  start_bridge

  if command -v dialog >/dev/null 2>&1 && [ -t 1 ]; then
    menu
  else
    clear; echo "Epilogue Operator bridge"; echo; status_text; echo; echo "Log: $LOG"; sleep 4
  fi
fi
