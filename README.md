# pspgo-flash

Every step of setting up and running a modded PSP Go, as one command line on your Mac.

```bash
git clone https://github.com/etiennedoidic/pspgo-flash.git
cd pspgo-flash
bash pspgo-setup.sh full
```

`full` walks you through the whole thing and waits on its own for the Go to reconnect. You only press Enter or answer y/n when something has to happen on the Go.

1. **preflight**: checks tools and finds the Go (`/Volumes/PSPGO`, plus `/Volumes/PSPGoSD` for the card)
2. **backup**: full copy of the Go to `backups/`
3. **firmware**: stages Sony's official PSP Go 6.61 update (needed from 6.39)
4. **ark**: downloads FasterARK (ARK-5) and copies it to the Go
5. **cipl**: makes ARK permanent
6. **wpa2**: turns on ARK's WPA2 Wi-Fi option
7. **profile**: pushes `profile/` (plugins, themes, wallpapers, apps, media)
8. **autosync**: from then on, plugging the Go in pushes `profile/` automatically

It's resumable: re-run `full` and finished steps are skipped. Use `full --reset` to start over or `full --from ark` to redo from a step.

## Everyday commands

| Command | What it does |
| --- | --- |
| `bash pspgo-setup.sh status` | What's connected, setup progress, last push |
| `bash pspgo-setup.sh push [--dry-run]` | Send `profile/` to the Go |
| `bash pspgo-setup.sh studio` | Web app: wallpapers, themes, plugins, Wi-Fi, library |
| `bash pspgo-setup.sh backup [--with-games]` / `restore [STAMP]` | Back up / restore the Go |
| `bash pspgo-setup.sh ark-update` | Stage the newest ARK updater |
| `bash pspgo-setup.sh autosync on\|off` | Auto-push when plugged in |
| `bash pspgo-setup.sh eject` | Eject both volumes |
| `bash pspgo-setup.sh self-update` | `git pull` this repo |

### Themes, wallpapers, plugins

```bash
bash pspgo-setup.sh cxmb install ~/Downloads/cxmb.zip   # flash-free CTF theme plugin
bash pspgo-setup.sh themes add ~/Downloads/MyTheme.ctf
bash pspgo-setup.sh wallpaper add ~/Pictures/desk.jpg     # cover-crops to 480x272
bash pspgo-setup.sh plugins list
bash pspgo-setup.sh plugins enable ef0:/SEPLUGINS/foo.prx game
bash pspgo-setup.sh push
```

`profile/seplugins/PLUGINS.TXT` is **merged** into the Go's copy on push, so changes made in ARK's own plugin menu are kept.

### Game library

`library/` is git-ignored, along with every `.iso`/`.cso` in the repo. Use your own disc dumps, PSN downloads and homebrew.

```bash
bash pspgo-setup.sh games add ~/Dumps/MyGame.iso   # -> library/ISO/
bash pspgo-setup.sh games push                     # -> PSPGoSD/ISO (or PSPGO if no card)
bash pspgo-setup.sh games pull                     # back up what's on the Go into library/
bash pspgo-setup.sh games list | space | remove NAME [--local]
```

## Studio

`bash pspgo-setup.sh studio` opens http://127.0.0.1:8478. It's Python 3 standard library only and listens on localhost only.

- **Wallpaper**: drop an image, pan/zoom on a 480×272 preview with a menu overlay, save
- **Themes**: drop `.ctf` files
- **Plugins**: edit `PLUGINS.TXT`
- **Wi-Fi**: type networks on the Mac. They're saved to `profile/wifi.json` (git-ignored) and pushed to the Go for the upcoming Join Wi-Fi app
- **Games**: library vs. what's on the Go, drop ISOs, copy to the Go
- **Device**: push, dry run, eject, setup progress

## Layout

```
pspgo-setup.sh     entry point
lib/               common, device, firmware, ark, sync, themes, games, full, studio
studio/            server.py + index.html
profile/           what gets pushed (tracked, except wifi.json and media files)
docs/              hardware (USB-C + video out, microSD), Wi-Fi notes
library/ backups/ downloads/ logs/   local only, git-ignored
```

Settings like volume names go in `config.local.sh` (see `config.example.sh`).

## Notes

- Built for macOS, using the stock bash 3.2, rsync, curl, unzip, diskutil and sips.
- The first time autosync runs, macOS may ask to let `bash` access removable volumes. Allow it.
- Keep the Go charging during the firmware and cIPL steps.
