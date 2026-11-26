#!/bin/bash
# librarian.sh: manage the PSP Go library on this Mac (games, music, video, pictures).
#
#   bash librarian.sh -a -g "games/Some Game (USA)"     add a game (ISO/CSO/EBOOT, or a folder/archive holding one)
#   bash librarian.sh -a -r -g ~/Dumps                  add every game found in a folder and its subfolders
#   bash librarian.sh -a -m ~/Music/Album               add music (the folder becomes an album on the Go)
#   bash librarian.sh -a -v clip.mp4                    add a video
#   bash librarian.sh -a -p ~/Pictures/Trip             add pictures
#   bash librarian.sh -a -r ~/Downloads/stuff           no type given: sorts each file by its format
#   bash librarian.sh -d -g "Some Game"                 remove from the Mac library (asks first)
#   bash librarian.sh -d -g "Some Game" --device        ...and from the Go too
#   bash librarian.sh -l [-g|-m|-v|-p]                  list the library
#   bash librarian.sh --push                            copy the library onto the Go (needs USB Connection)
#
# Options
#   -a, --add        add PATH...            -d, --remove     remove NAME... (case-insensitive match)
#   -l, --list       list                       --push       copy library to the Go after adding
#   -g, --game       games                  -m, --music      music
#   -v, --video      video                  -p, --picture    pictures
#   -r, --recursive  look inside subfolders     --device     with -d: also delete from the Go
#   -y, --yes        don't ask                  --force      accept a disc image that isn't a PSP game
#   -h, --help
#
# Archives (.zip, .7z, .rar) are checked and extracted to a temporary folder, then their
# contents are added. Every file's format is checked from its header bytes, not its name.
# Paths with spaces or brackets need quotes (or Tab-completion) in the shell.
#
# Where things go (all git-ignored):
#   games    -> library/ISO (.iso/.cso) or library/GAME/<folder> (EBOOT.PBP)   pushed by: games push
#   music    -> profile/media/MUSIC     video -> profile/media/VIDEO
#   pictures -> profile/media/PICTURE                                         pushed by: push
set -eo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export ROOT
. "$ROOT/lib/common.sh"
. "$ROOT/lib/device.sh"
load_config

MUSIC_DIR="$PROFILE/media/MUSIC"; VIDEO_DIR="$PROFILE/media/VIDEO"; PIC_DIR="$PROFILE/media/PICTURE"
mkdir -p "$MUSIC_DIR" "$VIDEO_DIR" "$PIC_DIR"
TMP_BASE="$DOWNLOADS/.librarian-tmp"

ADDED=0; SKIPPED=0; REJECTED=0

usage() { sed -n '2,/^set -eo/p' "$0" | sed '$d' | sed 's/^# \{0,1\}//'; }

# ---------- format checks (header bytes) ----------
hexat() { # FILE OFFSET COUNT -> lowercase hex
  dd if="$1" bs=1 skip="$2" count="$3" 2>/dev/null | od -An -tx1 | tr -d ' \n'
}
lower() { printf '%s' "$1" | tr 'A-Z' 'a-z'; }
ext_of() { local b; b=$(basename "$1"); case "$b" in *.*) lower "${b##*.}" ;; *) echo "" ;; esac; }

# kind_of FILE -> game-iso | game-cso | game-pbp | music | video | picture | archive | ""   (by extension)
kind_of() {
  case "$(ext_of "$1")" in
    iso) echo game-iso ;; cso|zso) echo game-cso ;; pbp) echo game-pbp ;;
    mp3|m4a|aac|wav|wma|oma|aa3|at3) echo music ;;
    mp4|m4v) echo video ;;
    jpg|jpeg|png|gif|bmp|tif|tiff) echo picture ;;
    zip|7z|rar) echo archive ;;
    *) echo "" ;;
  esac
}

# check_file FILE KIND -> 0 if the header matches the kind; prints the reason otherwise
check_file() {
  local f="$1" k="$2" size h
  [ -L "$f" ] && { echo "is a symlink"; return 1; }
  size=$(filesize "$f")
  [ "$size" -gt 0 ] || { echo "is empty"; return 1; }
  case "$k" in
    game-iso)
      [ $((size % 2048)) -eq 0 ] || { echo "size isn't a whole number of 2048-byte sectors (truncated download?)"; return 1; }
      [ "$(hexat "$f" 32769 5)" = "4344303031" ] || { echo "isn't an ISO-9660 disc image"; return 1; }
      if [ "$(dd if="$f" bs=1 skip=32776 count=8 2>/dev/null)" != "PSP GAME" ] && [ -z "$FORCE" ]; then
        echo "is a disc image, but not a PSP game (use --force to add anyway)"; return 1; fi ;;
    game-cso)
      h=$(hexat "$f" 0 4); [ "$h" = "4349534f" ] || [ "$h" = "5a49534f" ] || { echo "isn't a CSO/ZSO image"; return 1; } ;;
    game-pbp)
      [ "$(hexat "$f" 0 4)" = "00504250" ] || { echo "isn't a PSP EBOOT.PBP"; return 1; } ;;
    music)
      h=$(hexat "$f" 0 12)
      case "$h" in
        494433*|fff*) ;;                                   # MP3 (ID3 tag or frame sync)
        ????????66747970*) ;;                              # M4A/AAC in MP4 ("ftyp")
        52494646????????57415645) ;;                       # WAV
        3026b275*) ;;                                      # WMA (ASF)
        454133*|ea33*) ;;                                  # ATRAC (OMA/AA3)
        *) case "$h" in fff*|ffe*) ;; *) echo "doesn't look like MP3/AAC/WAV/WMA/ATRAC audio"; return 1 ;; esac ;;
      esac ;;
    video)
      [ "$(hexat "$f" 4 4)" = "66747970" ] || { echo "isn't an MP4 file"; return 1; } ;;
    picture)
      h=$(hexat "$f" 0 8)
      case "$h" in ffd8ff*|89504e470d0a1a0a|47494638*|424d*|49492a00*|4d4d002a*) ;;
        *) echo "isn't a JPEG/PNG/GIF/BMP/TIFF image"; return 1 ;; esac ;;
    archive)
      h=$(hexat "$f" 0 6)
      case "$h" in 504b0304*|377abcaf271c|526172211a07*) ;;
        *) echo "isn't a real zip/7z/rar archive"; return 1 ;; esac ;;
    *) echo "unknown type"; return 1 ;;
  esac
  # Last guard: nothing executable sneaks in under a media name.
  if command -v file >/dev/null; then
    case "$(file -b "$f" 2>/dev/null)" in
      *Mach-O*|*executable*|*script*text*) echo "is a program/script, not media"; return 1 ;;
    esac
  fi
  return 0
}

# ---------- archives ----------
# extract_archive ARCHIVE -> echoes a temp folder with the contents
extract_archive() {
  local a="$1" dest list bad need free
  mkdir -p "$TMP_BASE"; dest=$(mktemp -d "$TMP_BASE/x.XXXXXX")
  need=$(( $(filesize "$a") / 1024 * 3 ))           # guess: contents up to 3x the archive
  free=$(df -k "$DOWNLOADS" | awk 'NR==2{print $4}')
  [ "$free" -gt "$need" ] || { warn "Maybe not enough free space to extract $(basename "$a")"; }
  # List first and refuse entries that would land outside the folder (zip-slip).
  list=$(tar -tf "$a" 2>/dev/null) || list=$(unzip -Z1 "$a" 2>/dev/null) || list=""
  if [ -z "$list" ] && command -v 7zz >/dev/null; then list=$(7zz l -ba -slt "$a" | sed -n 's/^Path = //p'); fi
  [ -n "$list" ] || { rmdir "$dest"; echo ""; return 1; }
  bad=$(printf '%s\n' "$list" | grep -E '(^/|(^|/)\.\.(/|$))' || true)
  [ -z "$bad" ] || { warn "Refusing $(basename "$a"): it contains unsafe paths"; rmdir "$dest"; echo ""; return 1; }
  info "Extracting $(basename "$a") ($(human "$(filesize "$a")"))" >&2
  if ! tar -xf "$a" -C "$dest" 2>/dev/null; then
    if [ "$(ext_of "$a")" = zip ]; then unzip -q -o "$a" -d "$dest"
    elif command -v 7zz >/dev/null; then 7zz x -y -bso0 -o"$dest" "$a"
    elif command -v unar >/dev/null; then unar -q -f -o "$dest" "$a"
    else rm -rf "$dest"; warn "Can't open $(basename "$a"). Install a 7z tool: brew install sevenzip"; echo ""; return 1; fi
  fi
  find "$dest" -type l -exec rm -f {} + 2>/dev/null || true   # never follow links from an archive
  rm -rf "$dest/__MACOSX"
  echo "$dest"
}

# ---------- adding ----------
want() { # KIND -> 0 if the requested type accepts it
  case "$TYPE" in
    "") return 0 ;;
    game) case "$1" in game-*|archive) return 0 ;; esac ;;
    music|video|picture) [ "$1" = "$TYPE" ] || [ "$1" = archive ] && return 0 ;;
  esac
  return 1
}

copy_in() { # SRC DEST_DIR LABEL
  local src="$1" dir="$2" name; name=$(basename "$src")
  mkdir -p "$dir"
  if [ -e "$dir/$name" ] && [ "$(filesize "$dir/$name")" = "$(filesize "$src")" ]; then
    say "  = $name (already in the library)"; SKIPPED=$((SKIPPED+1)); return 0; fi
  if [ "$(filesize "$src")" -gt 104857600 ]; then
    with_progress "$dir/$name" $(( $(filesize "$src") / 1024 )) "$name" -- cp "$src" "$dir/$name"
  else cp "$src" "$dir/$name"; fi
  ok "$3: $name"; ADDED=$((ADDED+1))
}

add_file() { # FILE [ALBUM]   ALBUM = parent folder name for music/pictures
  local f="$1" album="${2:-}" k why
  case "$(basename "$f")" in ._*|.DS_Store) return 0 ;; esac
  k=$(kind_of "$f")
  [ -n "$k" ] || { [ -n "$VERBOSE_SKIP" ] && say "  - $(basename "$f") (not a game or media file)"; return 0; }
  want "$k" || return 0
  if ! why=$(check_file "$f" "$k"); then warn "Rejected $(basename "$f"): $why"; REJECTED=$((REJECTED+1)); return 0; fi
  case "$k" in
    game-iso|game-cso) copy_in "$f" "$LIBRARY/ISO" "game" ;;
    game-pbp)          add_eboot_dir "$(dirname "$f")" ;;
    music)   copy_in "$f" "$MUSIC_DIR${album:+/$album}" "music" ;;
    video)   copy_in "$f" "$VIDEO_DIR" "video" ;;
    picture) copy_in "$f" "$PIC_DIR${album:+/$album}" "picture" ;;
    archive)
      local x; x=$(extract_archive "$f") || { REJECTED=$((REJECTED+1)); return 0; }
      [ -n "$x" ] || { REJECTED=$((REJECTED+1)); return 0; }
      RECURSE_ONCE=1 add_dir "$x" "$(basename "${f%.*}")"
      rm -rf "$x" ;;
  esac
}

add_eboot_dir() { # FOLDER containing EBOOT.PBP -> library/GAME/FOLDER
  local d="$1" name; name=$(basename "$d")
  check_file "$d/EBOOT.PBP" game-pbp >/dev/null || { warn "Rejected $name: EBOOT.PBP isn't a PSP executable"; REJECTED=$((REJECTED+1)); return 0; }
  if [ -d "$LIBRARY/GAME/$name" ]; then say "  = $name (already in the library)"; SKIPPED=$((SKIPPED+1)); return 0; fi
  rsync -rt --exclude '._*' --exclude .DS_Store "$d" "$LIBRARY/GAME/"
  ok "game: $name (homebrew/PSN folder)"; ADDED=$((ADDED+1))
}

add_dir() { # DIR [ALBUM]   top level only, unless -r (or inside an archive)
  local d="$1" album="${2:-$(basename "$1")}" f depth=1
  if [ -f "$d/EBOOT.PBP" ] && want game-pbp; then add_eboot_dir "$d"; return 0; fi
  { [ -n "$RECURSIVE" ] || [ -n "$RECURSE_ONCE" ]; } && depth=20
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    # an EBOOT folder found while recursing is added as a whole
    if [ "$(basename "$f")" = EBOOT.PBP ]; then want game-pbp && add_eboot_dir "$(dirname "$f")"; continue; fi
    case "$f" in */EBOOT.PBP/*) continue ;; esac
    # music/pictures keep the folder they were in as the album name
    if [ "$(dirname "$f")" = "$d" ]; then add_file "$f" "$album"; else add_file "$f" "$(basename "$(dirname "$f")")"; fi
  done <<EOF
$(find "$d" -maxdepth "$depth" -type f 2>/dev/null | sort)
EOF
  if [ -z "$RECURSIVE" ] && [ -z "$RECURSE_ONCE" ] && [ -n "$(find "$d" -mindepth 2 -type f -print -quit 2>/dev/null)" ]; then
    info "$(basename "$d") has subfolders. Add -r to look inside them too."
  fi
}

do_add() {
  [ $# -gt 0 ] || die "Nothing to add. Example: bash librarian.sh -a -g \"games/My Game\""
  local p
  for p in "$@"; do
    if [ -f "$p" ]; then VERBOSE_SKIP=1 add_file "$p"
    elif [ -d "$p" ]; then head1 "Adding from $(basename "$p")${TYPE:+ ($TYPE)}"; add_dir "$p"
    else warn "Not found: $p  (quote paths with spaces or brackets)"; REJECTED=$((REJECTED+1)); fi
  done
  rmdir "$TMP_BASE" 2>/dev/null || true
  say ""; say "Added $ADDED, already there $SKIPPED, rejected $REJECTED."
  [ "$ADDED" -gt 0 ] && [ -z "$PUSH" ] && say "Copy to the Go with: bash librarian.sh --push"
  return 0
}

# ---------- listing / removing ----------
lib_dirs() { # TYPE -> "label|dir" lines
  case "${1:-}" in
    game)    printf 'game|%s\ngame|%s\n' "$LIBRARY/ISO" "$LIBRARY/GAME" ;;
    music)   printf 'music|%s\n' "$MUSIC_DIR" ;;
    video)   printf 'video|%s\n' "$VIDEO_DIR" ;;
    picture) printf 'picture|%s\n' "$PIC_DIR" ;;
    *) lib_dirs game; lib_dirs music; lib_dirs video; lib_dirs picture ;;
  esac
}

do_list() {
  local line label dir f
  head1 "Library on this Mac"
  while IFS= read -r line; do
    label=${line%%|*}; dir=${line#*|}
    for f in "$dir"/*; do
      [ -e "$f" ] || continue
      case "$(basename "$f")" in .gitkeep|.DS_Store) continue ;; esac
      printf '  %-8s %-50s %s\n' "$label" "$(basename "$f")" "$(du -sh "$f" 2>/dev/null | cut -f1)"
    done
  done <<EOF
$(lib_dirs "$TYPE")
EOF
  say "  ($(du -sh "$LIBRARY" "$PROFILE/media" 2>/dev/null | awk '{print $1}' | paste -sd+ - | sed 's/+/ + /') on disk)"
}

# device paths that mirror a library entry
device_paths() { # LABEL NAME
  local v
  for v in "$PSPGOSD_VOL" "$PSPGO_VOL"; do
    [ -d "$v" ] || continue
    case "$1" in
      game)    echo "$v/ISO/$2"; echo "$v/PSP/GAME/$2" ;;
      music)   echo "$v/MUSIC/$2" ;;
      video)   echo "$v/VIDEO/$2" ;;
      picture) echo "$v/PICTURE/$2" ;;
    esac
  done
}

do_remove() {
  [ $# -gt 0 ] || die "Say what to remove. Example: bash librarian.sh -d -g \"Some Game\""
  local q line label dir f n matches="" dev=""
  for q in "$@"; do
    while IFS= read -r line; do
      label=${line%%|*}; dir=${line#*|}
      for f in "$dir"/*; do
        [ -e "$f" ] || continue
        n=$(basename "$f"); case "$n" in .gitkeep) continue ;; esac
        case "$(lower "$n")" in *"$(lower "$q")"*) matches="$matches$label|$f
" ;; esac
      done
    done <<EOF
$(lib_dirs "$TYPE")
EOF
    if [ -n "$DEVICE" ]; then
      for line in game music video picture; do
        { [ -z "$TYPE" ] || [ "$TYPE" = "$line" ]; } || continue
        local v sub
        for v in "$PSPGOSD_VOL" "$PSPGO_VOL"; do
          [ -d "$v" ] || continue
          for sub in ISO PSP/GAME MUSIC VIDEO PICTURE; do
            case "$line:$sub" in game:ISO|game:PSP/GAME|music:MUSIC|video:VIDEO|picture:PICTURE) ;; *) continue ;; esac
            for f in "$v/$sub"/*; do
              [ -e "$f" ] || continue
              n=$(basename "$f")
              echo "$n" | grep -qE "$GAME_SKIP_RE" && continue
              case "$(lower "$n")" in *"$(lower "$q")"*) dev="$dev$f
" ;; esac
            done
          done
        done
      done
    fi
  done
  matches=$(printf '%s' "$matches" | sed '/^$/d' | sort -u); dev=$(printf '%s' "$dev" | sed '/^$/d' | sort -u)
  [ -n "$matches$dev" ] || { warn "Nothing matches: $*"; return 0; }
  head1 "Will delete"
  [ -n "$matches" ] && printf '%s\n' "$matches" | while IFS='|' read -r label f; do say "  Mac  $label  ${f#$ROOT/}"; done
  [ -n "$dev" ] && printf '%s\n' "$dev" | while IFS= read -r f; do say "  Go   $f"; done
  [ -n "$DEVICE" ] || { go_mounted && say "  (only the Mac copy; add --device to delete it from the Go too)"; }
  if [ -z "$PSPGO_YES" ]; then confirm "Delete these?" n || { say "Nothing deleted."; return 0; }; fi
  [ -n "$matches" ] && printf '%s\n' "$matches" | while IFS='|' read -r label f; do rm -rf "$f"; ok "Removed ${f#$ROOT/}"; done
  [ -n "$dev" ] && printf '%s\n' "$dev" | while IFS= read -r f; do rm -rf "$f"; ok "Removed $f"; done
  return 0
}

do_push() {
  bash "$ROOT/pspgo-setup.sh" games push
  bash "$ROOT/pspgo-setup.sh" push
}

# ---------- arguments ----------
GAME_SKIP_RE='^(UPDATE|FasterARK|FASTERARK|ARK_.*|CustomIPL|CIPL.*|ARK.*Updater)$'
ACTION=""; TYPE=""; RECURSIVE=""; DEVICE=""; FORCE=""; PUSH=""; ARGS=()
[ $# -gt 0 ] || { usage; exit 0; }
while [ $# -gt 0 ]; do
  case "$1" in
    -a|--add) ACTION=add ;;  -d|--remove|--rm) ACTION=remove ;;  -l|--list) ACTION=list ;;
    -g|--game) TYPE=game ;;  -m|--music) TYPE=music ;;  -v|--video) TYPE=video ;;  -p|--picture|--pictures) TYPE=picture ;;
    -r|--recursive) RECURSIVE=1 ;;  --device) DEVICE=1 ;;  --force) FORCE=1 ;;  -y|--yes) PSPGO_YES=1 ;;
    --push) PUSH=1 ;;  -h|--help) usage; exit 0 ;;
    --) shift; while [ $# -gt 0 ]; do ARGS+=("$1"); shift; done; break ;;
    -[a-z][a-z]*)  # combined short flags like -ar or -arg
      rest="${1#-}"; shift; set -- $(printf -- '-%s ' $(echo "$rest" | sed 's/./& /g')) "$@"; continue ;;
    -*) die "Unknown option: $1 (see: bash librarian.sh -h)" ;;
    *) ARGS+=("$1") ;;
  esac
  shift
done
[ -n "$DEVICE" ] && [ "$ACTION" = remove ] && ! go_mounted && warn "The Go isn't connected, so --device can only clean the Mac library."

case "$ACTION" in
  add)    do_add ${ARGS[@]+"${ARGS[@]}"} ;;
  remove) do_remove ${ARGS[@]+"${ARGS[@]}"} ;;
  list)   do_list ;;
  "")     [ -n "$PUSH" ] || { usage; exit 0; } ;;
esac
if [ -n "$PUSH" ]; then dev_require; do_push; fi
