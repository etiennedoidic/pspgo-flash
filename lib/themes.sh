# Themes (CTF via CXMB), wallpapers, and ARK plugins (SEPLUGINS/PLUGINS.TXT).

PLUGINS_FILE_REL="seplugins/PLUGINS.TXT"   # inside profile/

themes_cmd() {
  local d="$PROFILE/theme"; mkdir -p "$d"
  case "${1:-list}" in
    list)
      head1 "Themes in profile/theme"
      ls "$d"/*.ctf 2>/dev/null | xargs -n1 basename 2>/dev/null || say "  (none yet)"
      if go_mounted; then head1 "Themes on the Go"; ls "$PSPGO_VOL/PSP/THEME" 2>/dev/null || say "  (none)"; fi ;;
    add)
      shift; [ $# -gt 0 ] || die "Usage: themes add FILE.ctf [...]"
      local f; for f in "$@"; do
        case "$f" in *.ctf|*.CTF) cp "$f" "$d/" && ok "Added $(basename "$f")" ;; *) warn "Skipping $f (not a .ctf)" ;; esac
      done
      grep -q cxmb "$PROFILE/$PLUGINS_FILE_REL" 2>/dev/null || warn "CTF themes need CXMB: bash pspgo-setup.sh cxmb install ZIP"
      say "Push with: bash pspgo-setup.sh push, then on the Go: Settings > Theme Settings > Theme." ;;
    remove)
      [ -n "$2" ] || die "Usage: themes remove NAME"
      rm -f "$d/$2" "$d/$2.ctf"
      go_mounted && rm -f "$PSPGO_VOL/PSP/THEME/$2" "$PSPGO_VOL/PSP/THEME/$2.ctf"
      ok "Removed $2" ;;
    *) say "Usage: themes list|add FILE.ctf|remove NAME" ;;
  esac
}

# wallpaper add IMAGE [...]: cover-crop to 480x272 JPEG in profile/wallpapers/
wallpaper_cmd() {
  [ "${1:-}" = add ] || { say "Usage: wallpaper add IMAGE [...]"; ls "$PROFILE/wallpapers" 2>/dev/null; return 0; }
  shift; local d="$PROFILE/wallpapers" f out; mkdir -p "$d"
  for f in "$@"; do
    out="$d/$(basename "${f%.*}").jpg"
    if command -v sips >/dev/null; then
      local w h
      w=$(sips -g pixelWidth "$f" | awk '/pixelWidth/{print $2}')
      h=$(sips -g pixelHeight "$f" | awk '/pixelHeight/{print $2}')
      # scale so the image covers 480x272, then center-crop
      if [ $((w * 272)) -gt $((h * 480)) ]; then
        sips -s format jpeg --resampleHeight 272 "$f" --out "$out" >/dev/null
      else
        sips -s format jpeg --resampleWidth 480 "$f" --out "$out" >/dev/null
      fi
      sips -c 272 480 "$out" >/dev/null
    else
      cp "$f" "$out"; warn "sips not found; copied $f without resizing"
    fi
    ok "Wallpaper ready: profile/wallpapers/$(basename "$out")"
  done
  say "Push, then on the Go: Photo > Wallpapers > pick one > Triangle > Set as Wallpaper."
}

plugins_file() { mkdir -p "$PROFILE/seplugins"; touch "$PROFILE/$PLUGINS_FILE_REL"; echo "$PROFILE/$PLUGINS_FILE_REL"; }

# ARK format, one per line:  runlevel, path, on|off   (runlevel: vsh, game, pops, all, or a game ID)
plugins_cmd() {
  local pf; pf=$(plugins_file)
  case "${1:-list}" in
    list)
      head1 "profile/$PLUGINS_FILE_REL"; grep -v '^#' "$pf" | grep . || say "  (none)"
      if go_mounted && [ -f "$PSPGO_VOL/SEPLUGINS/PLUGINS.TXT" ]; then
        head1 "On the Go"; grep -v '^#' "$PSPGO_VOL/SEPLUGINS/PLUGINS.TXT" | grep . || true
      fi ;;
    enable|disable)
      [ -n "$2" ] || die "Usage: plugins $1 PATH_ON_GO [runlevel]   e.g. ef0:/SEPLUGINS/cxmb/cxmb.prx vsh"
      local path="$2" rl="${3:-vsh}" st=on tmp="$pf.tmp"
      [ "$1" = disable ] && st=off
      grep -vF ", $path," "$pf" > "$tmp" || true
      echo "$rl, $path, $st" >> "$tmp"; mv "$tmp" "$pf"
      ok "$path -> $st ($rl). Push to apply." ;;
    *) say "Usage: plugins list|enable PATH [runlevel]|disable PATH" ;;
  esac
}

# Merge profile PLUGINS.TXT into the Go's copy: profile lines win, others kept.
plugins_merge_to_device() {
  local pf="$PROFILE/$PLUGINS_FILE_REL" df="$PSPGO_VOL/SEPLUGINS/PLUGINS.TXT" tmp line path
  [ -s "$pf" ] || return 0
  mkdir -p "$PSPGO_VOL/SEPLUGINS"; touch "$df"; tmp="$df.pspgo.tmp"; cp "$df" "$tmp"
  while IFS= read -r line; do
    case "$line" in ''|\#*) continue ;; esac
    path=$(echo "$line" | cut -d, -f2 | sed 's/^ *//;s/ *$//')
    grep -vF ", $path," "$tmp" > "$tmp.2" || true; mv "$tmp.2" "$tmp"
    echo "$line" >> "$tmp"
  done < "$pf"
  mv "$tmp" "$df"
}

cxmb_cmd() {
  [ "${1:-}" = install ] && [ -n "$2" ] || { say "Usage: cxmb install CXMB_ZIP_OR_FOLDER"; return 0; }
  local src="$2" work="$DOWNLOADS/cxmb-extract" prx dir
  if [ -f "$src" ]; then rm -rf "$work"; mkdir -p "$work"; unzip -q -o "$src" -d "$work"; src="$work"; fi
  prx=$(find "$src" -iname cxmb.prx | head -1)
  [ -n "$prx" ] || die "No cxmb.prx found in $2"
  dir=$(dirname "$prx")
  mkdir -p "$PROFILE/seplugins/cxmb"
  rsync -rt "$dir/" "$PROFILE/seplugins/cxmb/"
  plugins_cmd enable "ef0:/SEPLUGINS/cxmb/cxmb.prx" vsh
  ok "CXMB is in the profile. Push, Restart VSH, then pick a theme in Settings > Theme Settings."
}
