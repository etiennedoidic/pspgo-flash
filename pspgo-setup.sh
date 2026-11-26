#!/bin/bash
# pspgo-flash: one command line for setting up, updating and managing a PSP Go.
#
#   bash pspgo-setup.sh full            guided first-time setup (resumable)
#   bash pspgo-setup.sh status          what's mounted, what stage you're at
#
#   Device
#   bash pspgo-setup.sh backup          full copy of the Go (and card) to backups/
#   bash pspgo-setup.sh restore [STAMP] copy a backup back onto the Go
#   bash pspgo-setup.sh eject           safely eject PSPGO and PSPGoSD
#
#   Updating the Go from this Mac
#   bash pspgo-setup.sh push [--dry-run]  sync profile/ (themes, plugins, apps, media, wifi) to the Go
#   bash pspgo-setup.sh firmware        stage Sony's official 6.61 update
#   bash pspgo-setup.sh ark             stage FasterARK (ARK-5 installer)
#   bash pspgo-setup.sh ark-update      stage the latest ARK updater
#   bash pspgo-setup.sh autosync on|off|run   push automatically when the Go is plugged in
#
#   Themes and plugins
#   bash pspgo-setup.sh themes list|add FILE.ctf|remove NAME
#   bash pspgo-setup.sh wallpaper add IMAGE        resize to 480x272, ready to push
#   bash pspgo-setup.sh plugins list|enable PRX [RUNLEVEL]|disable PRX
#   bash pspgo-setup.sh cxmb install ZIP_OR_DIR    flash-free CTF theme plugin
#   bash pspgo-setup.sh studio          web app for themes, wallpapers, wifi, library
#
#   Game library (library/ is git-ignored)
#   bash pspgo-setup.sh games list|add FILE...|push|pull|remove NAME|space
#
#   Repo
#   bash pspgo-setup.sh self-update     git pull this repo
#   bash pspgo-setup.sh help
set -eo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export ROOT
for f in "$ROOT"/lib/*.sh; do . "$f"; done
load_config

cmd="${1:-help}"; shift || true
case "$cmd" in
  full)        full_setup "$@" ;;
  status)      dev_status ;;
  backup)      dev_require; dev_backup ;;
  restore)     dev_require; dev_restore "$@" ;;
  eject)       dev_eject_all ;;
  push)        dev_require; sync_push "$@" ;;
  firmware)    dev_require; fw_stage; dev_eject_all; fw_instructions ;;
  ark)         dev_require; ark_stage; dev_eject_all; ark_instructions ;;
  ark-update)  dev_require; ark_update_stage; dev_eject_all ;;
  autosync)    autosync_cmd "$@" ;;
  themes)      themes_cmd "$@" ;;
  wallpaper)   wallpaper_cmd "$@" ;;
  plugins)     plugins_cmd "$@" ;;
  cxmb)        cxmb_cmd "$@" ;;
  games)       games_cmd "$@" ;;
  studio)      studio_start "$@" ;;
  self-update) repo_update ;;
  help|-h|--help) sed -n '2,/^set -eo/p' "$0" | sed '$d' | sed 's/^# \{0,1\}//' ;;
  *) die "Unknown command: $cmd. Try: bash pspgo-setup.sh help" ;;
esac
