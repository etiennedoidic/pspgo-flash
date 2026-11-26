# Shared helpers. Bash 3.2 compatible (stock macOS bash).

load_config() {
  # Defaults. Override any of these in config.local.sh (git-ignored).
  PSPGO_VOL="/Volumes/PSPGO"          # Go system storage (ef0)
  PSPGOSD_VOL="/Volumes/PSPGoSD"      # memory card (ms0)
  PROFILE="$ROOT/profile"
  LIBRARY="$ROOT/library"
  BACKUPS="$ROOT/backups"
  DOWNLOADS="$ROOT/downloads"
  LOGS="$ROOT/logs"
  STATE_FILE="$ROOT/.state"
  REPO_URL="https://github.com/etiennedoidic/pspgo-flash.git"
  STUDIO_PORT=8478
  AUTOSYNC_LABEL="com.pspgo-flash.autosync"
  # Official Sony 6.61 update for PSP Go (N1000). The non-Go file will not work.
  FW_URL="http://du01.psp.update.playstation.org/update/psp/image2/us/2014_1212_fd0f7d0798b4f6e6d32ef95836740527/EBOOT.PBP"
  ARK_REPO="PSP-Arkfive/FasterARK"
  [ -f "$ROOT/config.local.sh" ] && . "$ROOT/config.local.sh"
  mkdir -p "$BACKUPS" "$DOWNLOADS" "$LOGS" "$LIBRARY/ISO" "$LIBRARY/GAME"
  touch "$STATE_FILE"
}

# ---------- output ----------
if [ -t 1 ]; then B=$'\033[1m'; G=$'\033[32m'; Y=$'\033[33m'; R=$'\033[31m'; C=$'\033[36m'; N=$'\033[0m'
else B=""; G=""; Y=""; R=""; C=""; N=""; fi
say()   { printf '%s\n' "$*"; }
head1() { printf '\n%s== %s ==%s\n' "$B" "$*" "$N"; }
info()  { printf '%s>%s %s\n' "$C" "$N" "$*"; }
ok()    { printf '%s✓%s %s\n' "$G" "$N" "$*"; }
warn()  { printf '%s!%s %s\n' "$Y" "$N" "$*" >&2; }
die()   { printf '%s✗ %s%s\n' "$R" "$*" "$N" >&2; exit 1; }
onpsp() { printf '%s  [On the PSP]%s %s\n' "$B" "$N" "$*"; }

# ---------- input ----------
# confirm "Question" [default y|n]  -> returns 0 for yes
confirm() {
  local q="$1" d="${2:-y}" a hint="[Y/n]"
  [ "$d" = n ] && hint="[y/N]"
  if [ -n "$PSPGO_YES" ]; then [ "$d" = y ]; return; fi
  read -r -p "$q $hint " a </dev/tty || a=""
  a="${a:-$d}"
  case "$a" in y|Y|yes|YES) return 0 ;; *) return 1 ;; esac
}
# choose "Question" opt1 opt2 ...  -> echoes chosen option
choose() {
  local q="$1"; shift
  local i=1 o a
  if [ -n "$PSPGO_YES" ]; then  # non-interactive: first option, or PSPGO_CHOICE=n
    a="${PSPGO_CHOICE:-1}"; for o in "$@"; do [ "$i" = "$a" ] && { echo "$o"; return; }; i=$((i+1)); done
  fi
  printf '%s\n' "$q" >&2
  for o in "$@"; do printf '  %d) %s\n' "$i" "$o" >&2; i=$((i+1)); done
  while :; do
    read -r -p "Pick 1-$#: " a </dev/tty || a=""
    if [ "$a" -ge 1 ] 2>/dev/null && [ "$a" -le $# ]; then
      i=1; for o in "$@"; do [ "$i" = "$a" ] && { echo "$o"; return; }; i=$((i+1)); done
    fi
  done
}
pause() { [ -n "$PSPGO_YES" ] && return; read -r -p "${1:-Press Enter when done.} " _ </dev/tty || true; }

# ---------- state (key=value) ----------
state_get() { grep -E "^$1=" "$STATE_FILE" 2>/dev/null | tail -1 | cut -d= -f2-; }
state_set() {
  local tmp="$STATE_FILE.tmp"
  grep -vE "^$1=" "$STATE_FILE" > "$tmp" 2>/dev/null || true
  printf '%s=%s\n' "$1" "$2" >> "$tmp"
  mv "$tmp" "$STATE_FILE"
}
state_done() { [ "$(state_get "$1")" = done ]; }

# ---------- misc ----------
need_cmds() { local c; for c in "$@"; do command -v "$c" >/dev/null || die "Missing tool: $c"; done; }
filesize()  { stat -f%z "$1" 2>/dev/null || stat -c%s "$1"; }
human()     { awk -v b="$1" 'BEGIN{s="B KB MB GB TB";split(s,u," ");i=1;while(b>=1024&&i<5){b/=1024;i++};printf "%.1f %s",b,u[i]}'; }
is_mac()    { [ "$(uname)" = Darwin ]; }
notify()    { is_mac && osascript -e "display notification \"$1\" with title \"PSPGo\"" >/dev/null 2>&1 || true; }

# GitHub release asset URL matching a grep pattern, newest release first.
gh_asset_url() {
  local repo="$1" pattern="$2" exclude="${3:-^$}"
  curl -fsSL "https://api.github.com/repos/$repo/releases" \
    | grep -o '"browser_download_url": *"[^"]*"' \
    | sed 's/.*"\(http[^"]*\)"/\1/' \
    | grep -E "$pattern" | grep -viE "$exclude" | head -1
}

repo_update() {
  need_cmds git
  if [ ! -d "$ROOT/.git" ]; then
    info "Linking this folder to $REPO_URL"
    git -C "$ROOT" init -q -b main
    git -C "$ROOT" remote add origin "$REPO_URL"
  fi
  git -C "$ROOT" pull --ff-only origin main && ok "Up to date."
}
