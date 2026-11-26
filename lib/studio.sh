# PSPGo Studio: local web app (Python 3 standard library only).

studio_start() {
  command -v python3 >/dev/null || die "Studio needs python3 (macOS: xcode-select --install)."
  local port="${1:-$STUDIO_PORT}" url
  url="http://127.0.0.1:$port"
  info "PSPGo Studio at $url  (Ctrl-C to stop)"
  is_mac && (sleep 1; open "$url") &
  exec python3 "$ROOT/studio/server.py" --root "$ROOT" --port "$port"
}
