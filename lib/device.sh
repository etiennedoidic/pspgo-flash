# Finding, tagging, backing up and ejecting the PSP Go.

RSYNC_EXCLUDES="--exclude .Spotlight-V100 --exclude .fseventsd --exclude .Trashes --exclude ._* --exclude .DS_Store"

go_mounted() { [ -d "$PSPGO_VOL/PSP" ]; }
sd_mounted() { [ -d "$PSPGOSD_VOL" ]; }

# Wait (no typing needed) until the Go's storage shows up.
dev_wait() {
  go_mounted && return 0
  onpsp "Connect the USB cable, then Settings > USB Connection."
  printf 'Waiting for %s ' "$PSPGO_VOL"
  local n=0
  until go_mounted; do
    sleep 2; n=$((n+1)); printf '.'
    [ $((n % 30)) -eq 0 ] && printf '\n  (still waiting; is USB Connection open on the Go?) '
  done
  sleep 2; printf '\n'; ok "PSP Go connected."
}
dev_require() { dev_wait; }

# Wait until the Go has been unplugged / left USB mode.
dev_wait_gone() {
  go_mounted || return 0
  [ -n "$PSPGO_TEST" ] && return 0
  warn "The Go is still mounted. Eject it in Finder (or close USB Connection on the Go)."
  printf 'Waiting for the Go to disconnect '
  while go_mounted; do sleep 2; printf '.'; done; printf '\n'
}

dev_tag() {
  echo PSPGO > "$PSPGO_VOL/.pspgo-target"
  sd_mounted && echo PSPGOSD > "$PSPGOSD_VOL/.pspgo-target"
  return 0
}

dev_eject_all() {
  sync
  sd_mounted && { diskutil eject "$PSPGOSD_VOL" >/dev/null 2>&1 && ok "Ejected PSPGoSD" || warn "Couldn't eject PSPGoSD"; }
  go_mounted && { diskutil eject "$PSPGO_VOL" >/dev/null 2>&1 && ok "Ejected PSPGO" || warn "Couldn't eject PSPGO"; }
  return 0
}

# dev_backup [--with-games]
dev_backup() {
  local stamp dest need free games=""
  [ "$1" = "--with-games" ] && games=1
  stamp=$(date +%Y%m%d-%H%M%S); dest="$BACKUPS/$stamp"
  need=$(du -sk "$PSPGO_VOL" 2>/dev/null | cut -f1)
  free=$(df -k "$ROOT" | awk 'NR==2{print $4}')
  [ "$free" -gt $((need + 1048576)) ] || die "Not enough free space on this Mac for a backup ($(human $((need*1024))) needed)."
  head1 "Backup -> backups/$stamp"
  info "PSPGO ($(human $((need*1024)))): games, saves, settings"
  # shellcheck disable=SC2086
  rsync -rt $RSYNC_EXCLUDES "$PSPGO_VOL/" "$dest/PSPGO/"
  if sd_mounted; then
    info "PSPGoSD (without ISO/ unless --with-games)"
    local ex="--exclude ISO"; [ -n "$games" ] && ex=""
    # shellcheck disable=SC2086
    rsync -rt $RSYNC_EXCLUDES $ex "$PSPGOSD_VOL/" "$dest/PSPGoSD/"
  fi
  echo "$stamp" > "$BACKUPS/LATEST"
  ok "Backup done: backups/$stamp"
}

dev_restore() {
  local stamp="${1:-$(cat "$BACKUPS/LATEST" 2>/dev/null)}"
  [ -n "$stamp" ] && [ -d "$BACKUPS/$stamp/PSPGO" ] || die "No backup '$stamp'. See: ls backups/"
  warn "This copies backups/$stamp back onto the Go (files are added/overwritten, nothing deleted)."
  confirm "Restore now?" n || return 0
  # shellcheck disable=SC2086
  rsync -rt $RSYNC_EXCLUDES "$BACKUPS/$stamp/PSPGO/" "$PSPGO_VOL/"
  [ -d "$BACKUPS/$stamp/PSPGoSD" ] && sd_mounted && rsync -rt "$BACKUPS/$stamp/PSPGoSD/" "$PSPGOSD_VOL/"
  ok "Restored."
}

dev_status() {
  head1 "Devices"
  local v
  for v in "$PSPGO_VOL" "$PSPGOSD_VOL"; do
    if [ -d "$v" ]; then df -h "$v" | awk -v n="$v" 'NR==2{printf "  %-20s %s used of %s (%s free)\n", n, $3, $2, $4}'
    else printf '  %-20s not connected\n' "$v"; fi
  done
  head1 "Setup progress"
  local s
  for s in backup firmware ark cipl wpa2 profile autosync; do
    printf '  %-10s %s\n' "$s" "$(state_get "$s" || true)"
  done
  if go_mounted; then
    head1 "On the Go"
    [ -f "$PSPGO_VOL/PSP/GAME/UPDATE/EBOOT.PBP" ] && say "  6.61 update staged: run Game > System Storage > PSP Update"
    ark_present && say "  ARK files present" || say "  No ARK files yet"
    [ -f "$PSPGO_VOL/.pspgo-last-sync" ] && say "  Last push: $(cat "$PSPGO_VOL/.pspgo-last-sync")"
  fi
  [ -f "$BACKUPS/LATEST" ] && { head1 "Backups"; say "  Latest: backups/$(cat "$BACKUPS/LATEST")"; }
  return 0
}
