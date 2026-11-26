# Game library. library/ is git-ignored: games never go into the repo.
#   library/ISO/   .iso / .cso disc images (your own dumps)
#   library/GAME/  homebrew or PSN folders that contain EBOOT.PBP

# Folders in PSP/GAME that belong to the system/CFW, not the library.
GAME_SKIP='^(UPDATE|FasterARK|FASTERARK|ARK_.*|CustomIPL|CIPL.*|ARK.*Updater)$'

games_target() { if sd_mounted; then echo "$PSPGOSD_VOL"; else echo "$PSPGO_VOL"; fi; }

games_cmd() {
  local sub="${1:-list}"; shift || true
  case "$sub" in
    list)  games_list ;;
    add)   games_add "$@" ;;
    push)  dev_require; games_push "$@" ;;
    pull)  dev_require; games_pull ;;
    remove) dev_require; games_remove "$@" ;;
    space) dev_require; games_space ;;
    *) say "Usage: games list|add FILE...|push [--dry-run]|pull|remove NAME|space" ;;
  esac
}

_list_dir() { # dir type
  local d="$1" f
  [ -d "$d" ] || return 0
  for f in "$d"/*; do
    [ -e "$f" ] || continue
    printf '  %-9s %-45s %s\n' "$2" "$(basename "$f")" "$(du -sh "$f" 2>/dev/null | cut -f1)"
  done
}

games_list() {
  head1 "Library on this Mac (library/)"
  _list_dir "$LIBRARY/ISO" iso; _list_dir "$LIBRARY/GAME" folder
  local v
  for v in "$PSPGOSD_VOL" "$PSPGO_VOL"; do
    [ -d "$v" ] || continue
    head1 "On $(basename "$v")"
    _list_dir "$v/ISO" iso
    if [ -d "$v/PSP/GAME" ]; then
      { ls "$v/PSP/GAME" | grep -vE "$GAME_SKIP" || true; } | while read -r g; do
        printf '  %-9s %-45s %s\n' folder "$g" "$(du -sh "$v/PSP/GAME/$g" 2>/dev/null | cut -f1)"; done
    fi
  done
  return 0
}

games_add() {
  [ $# -gt 0 ] || die "Usage: games add FILE.iso|FILE.cso|FOLDER_WITH_EBOOT ..."
  local f
  for f in "$@"; do
    if [ -f "$f" ]; then
      case "$(echo "$f" | tr 'A-Z' 'a-z')" in
        *.iso|*.cso) cp "$f" "$LIBRARY/ISO/" && ok "library/ISO/$(basename "$f")" ;;
        *) warn "Skipping $f (need .iso, .cso, or a folder with EBOOT.PBP)" ;;
      esac
    elif [ -d "$f" ] && [ -f "$f/EBOOT.PBP" ]; then
      rsync -rt "$f" "$LIBRARY/GAME/" && ok "library/GAME/$(basename "$f")"
    elif [ -d "$f" ]; then
      # A folder of downloads/dumps: pick up every .iso/.cso inside it
      local found=0 img
      while IFS= read -r img; do
        [ -n "$img" ] || continue
        cp "$img" "$LIBRARY/ISO/" && ok "library/ISO/$(basename "$img")"; found=1
      done <<EOF2
$(find "$f" -type f \( -iname '*.iso' -o -iname '*.cso' \) 2>/dev/null)
EOF2
      if [ "$found" = 0 ]; then
        if find "$f" -iname '*.7z' -o -iname '*.rar' 2>/dev/null | grep -q .; then
          warn "$f has only archives (.7z/.rar). Extract them first (e.g. The Unarchiver), then add again."
        else warn "No .iso/.cso found in $f"; fi
      fi
    else warn "Skipping $f"; fi
  done
  say "Copy to the Go with: bash pspgo-setup.sh games push"
}

games_space() {
  local v; for v in "$PSPGO_VOL" "$PSPGOSD_VOL"; do
    [ -d "$v" ] && df -h "$v" | awk -v n="$(basename "$v")" 'NR==2{printf "  %-10s %s free of %s\n", n, $4, $2}'
  done
  printf '  %-10s %s\n' library "$(du -sh "$LIBRARY" | cut -f1)"
}

games_push() {
  local t dry=""; t=$(games_target)
  [ "${1:-}" = --dry-run ] && dry="-n -v"
  local need free
  need=$(du -sk "$LIBRARY" | cut -f1); free=$(df -k "$t" | awk 'NR==2{print $4}')
  [ -n "$dry" ] || [ "$free" -gt "$need" ] || warn "Library ($(human $((need*1024)))) may not fit on $(basename "$t") ($(human $((free*1024))) free). rsync skips what's already there."
  head1 "Pushing library -> $(basename "$t")"
  mkdir -p "$t/ISO" "$t/PSP/GAME"
  # shellcheck disable=SC2086
  rsync -rt $dry --progress $RSYNC_EXCLUDES "$LIBRARY/ISO/" "$t/ISO/"
  # shellcheck disable=SC2086
  rsync -rt $dry $RSYNC_EXCLUDES "$LIBRARY/GAME/" "$t/PSP/GAME/"
  ok "Done. ISOs show up under Game > Memory Stick (ARK)."
}

games_pull() {
  local v g
  head1 "Copying games from the Go into library/"
  for v in "$PSPGO_VOL" "$PSPGOSD_VOL"; do
    [ -d "$v" ] || continue
    # shellcheck disable=SC2086
    if [ -d "$v/ISO" ]; then rsync -rt $RSYNC_EXCLUDES "$v/ISO/" "$LIBRARY/ISO/"; fi
    if [ -d "$v/PSP/GAME" ]; then
      { ls "$v/PSP/GAME" | grep -vE "$GAME_SKIP" || true; } | while read -r g; do
        rsync -rt "$v/PSP/GAME/$g" "$LIBRARY/GAME/" && say "  $g"; done
    fi
  done
  ok "Library: $(du -sh "$LIBRARY" | cut -f1). Saves are covered by: bash pspgo-setup.sh backup"
}

games_remove() {
  [ -n "${1:-}" ] || die "Usage: games remove NAME [--local]"
  local name="$1" hit="" v p
  for v in "$PSPGOSD_VOL" "$PSPGO_VOL"; do
    for p in "$v/ISO/$name" "$v/PSP/GAME/$name"; do
      [ -e "$p" ] || continue
      confirm "Delete $p from the Go?" n && { rm -rf "$p"; ok "Removed $p"; }
      hit=1
    done
  done
  if [ "${2:-}" = --local ]; then
    for p in "$LIBRARY/ISO/$name" "$LIBRARY/GAME/$name"; do
      [ -e "$p" ] && confirm "Also delete $p from this Mac?" n && { rm -rf "$p"; ok "Removed $p"; hit=1; }
    done
  fi
  [ -n "$hit" ] || warn "No game named '$name'. See: bash pspgo-setup.sh games list"
}
