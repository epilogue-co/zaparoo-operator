# MiSTer deployment

This folder is an overlay onto the MiSTer SD card root (`/media/fat`). Layout
mirrors the card so files drop straight into place:

```
Scripts/Operator.sh             -> /media/fat/Scripts/Operator.sh      (F12 -> Scripts menu entry + manager)
Scripts/.operator/zaparoo-operator  the ARM bridge binary (copied from ../../dist at install time)
```

`/media/fat/linux/user-startup.sh` is NOT part of this overlay and isn't
shipped in the release zip — `Operator.sh` creates or safely merges into it
at runtime (see "How it works" below), so extracting this overlay can never
clobber a user's other autostart entries.

## Install

Easiest path: download `zaparoo-operator-mister-*.zip` from
[Releases](https://github.com/epilogue-co/zaparoo-operator/releases) — it's
already laid out exactly like this folder, binary included — and extract it
onto the SD card root (`/media/fat`). Then skip to step 3 below.

Building from source instead:

1. Build the release archive (static ARMv7 binary + this overlay, zipped):

   ```sh
   make release   # -> dist/zaparoo-operator-mister-<version>.zip
   ```

   Or just the binary, if you're copying files by hand:

   ```sh
   make mister    # -> dist/zaparoo-operator-mister
   ```

2. Extract the release zip onto the card, or copy the individual files
   (replace `/Volumes/MiSTer_Data` with your mount):

   ```sh
   M=/Volumes/MiSTer_Data
   mkdir -p "$M/Scripts/.operator"
   cp dist/zaparoo-operator-mister      "$M/Scripts/.operator/zaparoo-operator"
   cp deploy/mister/Scripts/Operator.sh "$M/Scripts/Operator.sh"
   cp -R deploy/mister/Scripts/.operator/sounds "$M/Scripts/.operator/"
   chmod +x "$M/Scripts/.operator/zaparoo-operator" "$M/Scripts/Operator.sh"
   ```

3. On the MiSTer: **F12 -> Scripts -> Operator**. First run installs the Zaparoo
   config, enables boot autostart, starts the bridge, and shows the manager menu.

## How it works

- `Operator.sh` is both the installer and the runtime manager (start / stop /
  restart / enable-disable autostart / view log / uninstall) via a `dialog` menu.
- `Operator.sh` manages `/media/fat/linux/user-startup.sh` itself: creates it
  with a shebang if missing, otherwise idempotently strips and re-appends only
  its own `#==== Epilogue Operator BEGIN/END ====` block, leaving every other
  line (Zaparoo's own autostart hook, other scripts, etc.) untouched. `$1 !=
  "stop"` keeps our line out of the shutdown path. The block also starts the
  Zaparoo service: some images (SuperStation One) ship Zaparoo preinstalled
  but never start it at boot.
- The bridge owns the Operator's `/dev/ttyACM*` exclusively, so Zaparoo runs with
  `auto_detect = false`; the explicit `file` reader watches the token the bridge
  writes. Hold mode returns to the menu when the cartridge is removed.
- After any config write, `zaparoo.sh -reload` pushes the change into a running
  service — Zaparoo keeps its config in memory and writes that memory back on
  any settings change, which would otherwise revert our edit.
- Zaparoo Core older than v2.9.1 mishandles hold mode (a quick cartridge swap
  is swallowed; reader glitches can exit games); the installer warns on every
  run — every run, because a Console Mode install can silently downgrade Core.
- The menu header shows the whole stack at a glance — bridge build, Zaparoo
  Core version, and live service state — and menu item 7 renders a one-page
  "status snapshot" (versions, config state, tails of both the bridge log and
  Zaparoo's own error log) designed to be photographed for support.

## Updating Zaparoo Core

The Operator needs Zaparoo Core **v2.9.1 or newer** (current release
recommended); the installer tells you the version it found when it's too old.
Three updates that look like they update Zaparoo but don't:

- **Update All skips Zaparoo by default.** It's an opt-in database: run
  `update_all`, press **UP during the countdown** to open settings, enable
  **Zaparoo** under *Tools & Scripts*, save, and let the update run.
- **Console Mode installs/updates can DOWNGRADE it** — they ship their own
  bundled `zaparoo.sh` and overwrite yours. If the old-version warning comes
  back after a Console Mode update, that's why; just update Core again.
- **Zaparoo's own in-app/TUI update** refreshes its media database, not the
  Core binary.

The deterministic route: download `zaparoo-mister_arm-<version>.zip` from
zaparoo.org (or github.com/ZaparooProject/zaparoo-core/releases) on a PC,
copy `zaparoo.sh` over `/media/fat/Scripts/zaparoo.sh`, and reboot. Don't
download it *on* the console right after boot — on units without an RTC
battery the clock starts at 1970 and TLS fails until NTP syncs.

The menu's `Zaparoo:` line always shows the version actually installed on
disk, so a single menu photo confirms whether an update took.

## SuperStation One

The SuperStation One works out of the box, with two differences the installer
handles automatically:

- Its built-in NFC reader (a PN532-compatible chip behind a CH340 USB-UART
  bridge) is normally found by Zaparoo's auto-detection, which the Operator
  config turns off. The installer detects the console and pins the reader with
  an explicit `pn532_uart` entry (via its stable `/dev/serial/by-path` name),
  so the built-in NFC keeps working.
- The stock image never starts the Zaparoo service at boot; our autostart
  block does.

Notes for SuperStation One users:

- While the Operator bridge is installed, Zaparoo runs in hold mode globally:
  an NFC card tap launches its game, but the game exits ~2.5 s after the card
  leaves the pad. NFC buttons/stickers that stay in place are unaffected.
- The stock image ships Zaparoo Core v2.6.2 — update it (see "Updating
  Zaparoo Core" above) when the installer suggests it. On stock v2.6.2,
  cartridge launches are unreliable; updating Core is part of the install.
- Firmware updates are full SD reflashes: re-extract the release zip and re-run
  `Operator.sh` afterwards.
- Everything USB on the console shares one internal hub and one USB-C supply;
  use a proper 5V/3A or 9V PD power supply, especially with the Operator's bus
  power added.

## Troubleshooting

- **Menu says "Playing X" but nothing launches:** the bridge is fine (it read
  the cart and wrote the launch); the Zaparoo side isn't consuming it. Check
  the menu's `Zaparoo:` line — `service ERROR` or an old version is the
  cause. Update Core (above) and reboot.
- **Reporting a problem:** menu item 7 (*Status snapshot*) puts everything a
  report needs on one screen — photograph it. It includes the recent errors
  from Zaparoo's own log, which is where launch failures explain themselves.
- **The Operator disconnects mid-game:** the bridge now rides out transient
  drops (up to 10 s) without stopping the game, and logs the kernel's USB
  lines (`kernel: ...`) explaining the disconnect — include them in reports.
