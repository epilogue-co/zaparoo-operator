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
  "stop"` keeps our line out of the shutdown path.
- The bridge owns the Operator's `/dev/ttyACM*` exclusively, so Zaparoo runs with
  `auto_detect = false`; the explicit `file` reader watches the token the bridge
  writes. Hold mode returns to the menu when the cartridge is removed.
