# zaparoo-operator

Bridges an Epilogue Operator (GB / SNES / N64 — same host protocol across all
three) to FPGA-accurate cores on MiSTer-class hardware, including Taki Udon's
SuperStation One, through [Zaparoo](https://zaparoo.org/).

Insert a cartridge, it boots straight into the matching core. Pull it, you're
back at the menu. Saves get written back to the cartridge automatically while
you play. No `Main_MiSTer` fork, no Zaparoo fork.

## Install

Grab the latest `zaparoo-operator-mister-*.zip` from
[Releases](https://github.com/epilogue-co/zaparoo-operator/releases) and
extract it onto your SD card root — it drops straight into `/media/fat`.

Then on the MiSTer: F12 -> Scripts -> Operator. First run sets up the Zaparoo
config, turns on autostart, and starts the bridge. That same menu entry is
also the manager afterwards — start/stop, autostart on/off, live log,
uninstall. See `deploy/mister/README.md` for exactly what the installer does.

## What it does

On insert, the bridge verifies the cartridge is real, reads the ROM into a
RAM-backed scratch dir (never the SD card — nothing left behind if you pull
the cart mid-session), seeds the emulator save from the cartridge, and
launches the matching core through Zaparoo. Once the core has loaded the ROM,
the working copy is deleted — the game runs from SDRAM.

While you play, the bridge watches the core's save file and writes any
change back to the cartridge, verifying each write before trusting it. Pull
the cartridge and it does one last flush, then wipes its working copies.
Nothing outlives the session except what's actually on the cartridge.

## Supported systems

| System | notes |
|---|---|
| Game Boy / Color | |
| Game Boy Advance | |
| Super Nintendo | title shown is a generated name for now |
| Nintendo 64 | save write-back is experimental |

## Notes

- The daemon (protocol layer, save-format handling, MiSTer integration) is
  closed source. This repo distributes prebuilt binaries and the installer.
- Validated against a connected Operator at the protocol and bridge layers;
  treat the first real hardware run as a smoke test.
