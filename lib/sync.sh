# Push profile/ to the Go, and auto-push on plug-in.

# sync_push [--dry-run] [--quiet]
sync_push() {
  local dry="" quiet="" a
  for a in "$@"; do case "$a" in --dry-run) dry="-n -v" ;; --quiet) quiet=1 ;; esac; done
  local media_root="$PSPGO_VOL"; sd_mounted && media_root="$PSPGOSD_VOL"
  [ -z "$quiet" ] && head1 "Pushing profile/ to the Go${dry:+ (dry run)}"

  _push() { # src dest label
    [ -d "$1" ] || return 0
    [ -n "$(ls -A "$1" 2>/dev/null | grep -v '^\.gitkeep$')" ] || return 0
    mkdir -p "$2"
    # shellcheck disable=SC2086
    rsync -rt $dry $RSYNC_EXCLUDES --exclude .gitkeep "$1/" "$2/"
    [ -z "$quiet" ] && ok "$3"
    return 0
  }
  # PLUGINS.TXT is merged (ARK's own plugin menu edits it too), everything else copied.
  if [ -d "$PROFILE/seplugins" ]; then
    mkdir -p "$PSPGO_VOL/SEPLUGINS"
    # shellcheck disable=SC2086
    rsync -rt $dry $RSYNC_EXCLUDES --exclude .gitkeep --exclude PLUGINS.TXT "$PROFILE/seplugins/" "$PSPGO_VOL/SEPLUGINS/"
    [ -z "$dry" ] && plugins_merge_to_device
    [ -z "$quiet" ] && ok "plugins  -> PSPGO/SEPLUGINS (PLUGINS.TXT ${dry:+would be }merged)"
  fi
  _push "$PROFILE/theme"         "$PSPGO_VOL/PSP/THEME"                "themes   -> PSPGO/PSP/THEME"
  _push "$PROFILE/wallpapers"    "$PSPGO_VOL/PICTURE/Wallpapers"       "walls    -> PSPGO/PICTURE/Wallpapers"
  _push "$PROFILE/apps"          "$PSPGO_VOL/PSP/GAME"                 "apps     -> PSPGO/PSP/GAME"
  _push "$PROFILE/media/MUSIC"   "$media_root/MUSIC"                   "music    -> $(basename "$media_root")/MUSIC"
  _push "$PROFILE/media/VIDEO"   "$media_root/VIDEO"                   "video    -> $(basename "$media_root")/VIDEO"
  _push "$PROFILE/media/PICTURE" "$media_root/PICTURE"                 "pictures -> $(basename "$media_root")/PICTURE"
  if [ -f "$PROFILE/wifi.json" ] && [ -z "$dry" ]; then
    mkdir -p "$PSPGO_VOL/PSP/COMMON/pspgo" && cp "$PROFILE/wifi.json" "$PSPGO_VOL/PSP/COMMON/pspgo/wifi.json"
    [ -z "$quiet" ] && ok "wifi     -> PSPGO/PSP/COMMON/pspgo/wifi.json"
  fi
  [ -z "$dry" ] && date "+%Y-%m-%d %H:%M" > "$PSPGO_VOL/.pspgo-last-sync"
  [ -z "$quiet" ] && [ -z "$dry" ] && onpsp "Press SELECT > Restart VSH to load changes."
  return 0
}

autosync_plist() { echo "$HOME/Library/LaunchAgents/$AUTOSYNC_LABEL.plist"; }

autosync_cmd() {
  case "${1:-}" in
    on)
      is_mac || die "autosync uses launchd (macOS only)."
      local p; p=$(autosync_plist); mkdir -p "$(dirname "$p")"
      cat > "$p" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>$AUTOSYNC_LABEL</string>
  <key>ProgramArguments</key><array>
    <string>/bin/bash</string><string>$ROOT/pspgo-setup.sh</string><string>autosync</string><string>run</string>
  </array>
  <key>StartOnMount</key><true/>
  <key>StandardOutPath</key><string>$LOGS/autosync.log</string>
  <key>StandardErrorPath</key><string>$LOGS/autosync.log</string>
</dict></plist>
EOF
      launchctl unload "$p" 2>/dev/null || true
      launchctl load "$p"
      state_set autosync done
      ok "Auto-push is on: plugging the Go in (USB Connection) pushes profile/ and ejects."
      info "First run, macOS may ask to let bash access removable volumes. Allow it." ;;
    off)
      local p; p=$(autosync_plist)
      launchctl unload "$p" 2>/dev/null || true; rm -f "$p"
      state_set autosync off; ok "Auto-push is off." ;;
    run)
      # Called by launchd on any volume mount. Silent unless it's the tagged Go.
      sleep 4                                   # let both volumes finish mounting
      go_mounted && [ -f "$PSPGO_VOL/.pspgo-target" ] || exit 0
      [ "$(state_get setup)" = done ] || exit 0  # don't interfere with first-time setup
      mkdir "$ROOT/.autosync.lock" 2>/dev/null || exit 0
      trap 'rmdir "$ROOT/.autosync.lock"' EXIT
      echo "$(date) push start"
      sync_push --quiet && echo "$(date) push done"
      [ "${AUTOSYNC_EJECT:-1}" = 1 ] && dev_eject_all
      notify "Profile pushed. Restart VSH on the Go." ;;
    *) say "Usage: bash pspgo-setup.sh autosync on|off|run" ;;
  esac
}
