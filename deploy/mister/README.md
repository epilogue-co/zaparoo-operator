# MiSTer deployment

This folder is an overlay onto the MiSTer SD card root (`/media/fat`). Layout
mirrors the card so files drop straight into place:

```
Scripts/Operator.sh             -> /media/fat/Scripts/Operator.sh      (F12 -> Scripts menu entry + manager)
Scripts/.operator/zaparoo-operator  the ARM bridge binary
linux/user-startup.sh           -> /media/fat/linux/user-startup.sh    (boot autostart, marker block)
zaparoo/config.toml             written by Operator.sh on first run if absent
```

## Install

Download `zaparoo-operator-mister-*.zip` from
[Releases](https://github.com/epilogue-co/zaparoo-operator/releases) — it's
already laid out exactly like this folder, binary included — and extract it
onto the SD card root (`/media/fat`).

On the MiSTer: **F12 -> Scripts -> Operator**. First run installs the Zaparoo
config, enables boot autostart, starts the bridge, and shows the manager menu.

## How it works

- `Operator.sh` is both the installer and the runtime manager (start / stop /
  restart / enable-disable autostart / view log / uninstall) via a `dialog` menu.
- `user-startup.sh` is MiSTer's update-safe autostart hook. Our line lives in an
  idempotent `#==== Epilogue Operator BEGIN/END ====` block so it can be
  re-applied or stripped cleanly, and it coexists with Zaparoo's `mrext/zaparoo`
  line. `$1 != "stop"` keeps it out of the shutdown path.
- The bridge owns the Operator's `/dev/ttyACM*` exclusively, so Zaparoo runs with
  `auto_detect = false`; the explicit `file` reader watches the token the bridge
  writes. Hold mode returns to the menu when the cartridge is removed.
