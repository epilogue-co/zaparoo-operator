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
uninstall.

The Operator needs Zaparoo Core v2.9.1+ — the menu warns if yours is older.

## Update

- **Operator:** automatic. The release zip includes
  `downloader_operator.ini`, which enrolls the Operator in MiSTer Downloader
  / `update_all` updates. An update run fetches the new build and prompts
  the usual reboot to activate it; opening Scripts -> Operator also switches
  a running bridge to a newly installed build. (Delete that file from the SD
  root to opt out; manual updates then work as before: **Stop bridge**,
  extract the new zip over `/media/fat`, reopen Scripts -> Operator.)
- **Zaparoo Core:** use `update_all`: enable **Zaparoo** under its
  *Tools & Scripts* settings first (it's off by default), then update as
  usual. On Core v2.16.0+ the Operator uses Zaparoo's built-in integration
  and honors your configured launcher preferences.

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

## SuperStation One

Update your Zaparoo installation using https://github.com/theypsilon/Update_All_MiSTer.

## Troubleshooting

The menu header shows the whole stack: bridge build, Zaparoo Core version,
and live service state. "Playing X" with nothing on screen means the Zaparoo
side is down or outdated — update Core and reboot. To report a problem, use
menu item 7 (*Status snapshot*) and photograph the screen; it carries the
versions, config state, and recent errors from both logs.

## Notes

- The daemon (protocol layer, save-format handling, MiSTer integration) is
  closed source. This repo distributes prebuilt binaries and the installer.
- Validated against a connected Operator at the protocol and bridge layers;
  treat the first real hardware run as a smoke test.
