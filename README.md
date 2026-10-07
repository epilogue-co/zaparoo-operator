# zaparoo-operator

A bridge that plays cartridges from an Epilogue Operator, a USB cartridge
reader, on MiSTer FPGA cores through [Zaparoo](https://zaparoo.org/). Insert a
cartridge and the matching core boots. Remove it and MiSTer returns to the
menu. The bridge writes saves back to the cartridge while you play.

Supports Game Boy, Game Boy Color, Game Boy Advance, Super Nintendo, and
Nintendo 64 (N64 save write-back is experimental). Runs on MiSTer and on Taki
Udon's SuperStation One.

## Install

1. Install Zaparoo Core v2.9.1 or newer with `update_all`: press Up during
   its countdown, enable **Zaparoo** under **Tools & Scripts**, then save and
   run the update. The SuperStation One ships with v2.6.2 and needs this step.
2. Extract the latest `zaparoo-operator-mister-*.zip` from
   [Releases](https://github.com/epilogue-co/zaparoo-operator/releases) to the
   SD card root.
3. On the MiSTer, open F12 -> Scripts -> Operator. The first run configures
   Zaparoo, enables autostart, and starts the bridge.

`update_all` installs new bridge builds from then on. Scripts -> Operator also
opens the manager menu: start, stop, autostart, logs, uninstall, and a status
snapshot to photograph for bug reports.
