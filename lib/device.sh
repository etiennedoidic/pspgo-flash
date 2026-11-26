# Finding, tagging, backing up and ejecting the PSP Go.

RSYNC_EXCLUDES="--exclude .Spotlight-V100 --exclude .fseventsd --exclude .Trashes --exclude ._* --exclude .DS_Store"

go_mounted() { [ -d "$PSPGO_VOL/PSP" ]; }
sd_mounted() { [ -d "$PSPGOSD_VOL" ]; }

# If the default volume names aren't there, look for PSP volumes and remember them.
dev_detect() {
  go_mounted && return 0
  is_mac || return 0
  local v cands="" n
  for v in /Volumes/*; do
    if [ -d "$v/PSP" ] && [ "$v" != "$PSPGOSD_VOL" ]; then cands="$cands$v
"; fi
  done
  cands=$(printf '%s' "$cands" | sed '/^$/d')
  [ -n "$cands" ] || return 0
  n=$(printf '%s\n' "$cands" | wc -l | tr -d ' ')
  printf '\n'
  if [ "$n" = 1 ]; then
    confirm "Found $cands. Is that the Go's internal storage (not the memory card)?" y || return 0
    PSPGO_VOL="$cands"
  else
    local IFS=$'\n'
    PSPGO_VOL=$(choose "Found more than one PSP volume. Which is the Go's internal storage (about 16 GB)?" $cands)
    for v in $cands; do
      if [ "$v" != "$PSPGO_VOL" ]; then PSPGOSD_VOL="$v"; fi
    done
  fi
  printf 'PSPGO_VOL="%s"\nPSPGOSD_VOL="%s"\n' "$PSPGO_VOL" "$PSPGOSD_VOL" > "$ROOT/config.local.sh"
  ok "Using $PSPGO_VOL for the Go (saved in config.local.sh)"
  return 0
}

# Wait (no typing needed) until the Go's storage shows up.
dev_wait() {
  dev_detect
  go_mounted && return 0
  [ -n "$DEV_WAIT_QUIET" ] || todo "connect the Go" "Plug the Go into the Mac with its USB cable." "On the Go: Settings > USB Connection (press X)."
  printf 'Waiting for the Go to appear on the Mac (I continue by myself) '
  local n=0
  until go_mounted; do
    sleep 2; n=$((n+1)); printf '.'; dev_detect
    [ $((n % 30)) -eq 0 ] && printf '\n  (still waiting; is USB Connection open on the Go?) '
  done
  sleep 2; printf '\n'; ok "PSP Go connected."
}
dev_require() { dev_wait; }

# Wait until the Go has been unplugged / left USB mode.
dev_wait_gone() {
  go_mounted || return 0
  [ -n "$PSPGO_TEST" ] && return 0
  printf 'Waiting for the Go to be ejected (I continue by myself) '
  while go_mounted; do sleep 2; printf '.'; done; printf '\n'
}

dev_tag() {
  echo PSPGO > "$PSPGO_VOL/.pspgo-target"
  sd_mounted && echo PSPGOSD > "$PSPGOSD_VOL/.pspgo-target"
  return 0
}

# eject_vol PATH LABEL -- eject, retry once, then say what's holding it.
eject_vol() {
  local v="$1" l="$2" err
  [ -d "$v" ] || return 0
  err=$(diskutil eject "$v" 2>&1) && { ok "Ejected $l"; return 0; }
  sleep 3; mdutil -i off "$v" >/dev/null 2>&1 || true   # Spotlight often holds new volumes
  err=$(diskutil eject "$v" 2>&1) && { ok "Ejected $l"; return 0; }
  warn "Couldn't eject $l: ${err##*: }"
  local who; who=$(lsof "$v" 2>/dev/null | awk 'NR>1{print $1}' | sort -u | tr '\n' ' ')
  [ -n "$who" ] && warn "  In use by: $who(close those, or quit Finder windows on it)"
  warn "  To force it: diskutil unmount force \"$v\""
  return 0
}

dev_eject_all() {
  sync
  sd_mounted && eject_vol "$PSPGOSD_VOL" PSPGoSD
  go_mounted && eject_vol "$PSPGO_VOL" PSPGO
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
  mkdir -p "$dest/PSPGO"   # macOS rsync 2.6.9 won't create parent folders
  # shellcheck disable=SC2086
  with_progress "$dest/PSPGO" "$need" "PSPGO" -- rsync -rt $RSYNC_EXCLUDES "$PSPGO_VOL/" "$dest/PSPGO/"
  if sd_mounted; then
    info "PSPGoSD (without ISO/ unless --with-games)"
    local ex="--exclude ISO"; [ -n "$games" ] && ex=""
    mkdir -p "$dest/PSPGoSD"
    # shellcheck disable=SC2086
    local sdneed; sdneed=$(du -sk $([ -z "$games" ] && echo "-I ISO") "$PSPGOSD_VOL" 2>/dev/null | cut -f1)
    with_progress "$dest/PSPGoSD" "${sdneed:-0}" "PSPGoSD" -- rsync -rt $RSYNC_EXCLUDES $ex "$PSPGOSD_VOL/" "$dest/PSPGoSD/"
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
