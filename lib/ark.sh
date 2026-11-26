# ARK-5 custom firmware via FasterARK.

ark_present() {
  [ -d "$PSPGO_VOL/PSP/SAVEDATA/ARK_01234" ] && return 0
  ls -d "$PSPGO_VOL"/PSP/GAME/*ARK* "$PSPGO_VOL"/PSP/GAME/*Fast* >/dev/null 2>&1
}

# Download a release zip matching PATTERN into downloads/ and echo its path.
ark_fetch() {
  local pattern="$1" exclude="$2" zip url
  zip=$(ls "$DOWNLOADS"/* 2>/dev/null | grep -E "$pattern" | grep -viE "${exclude:-^$}" | head -1 || true)
  if [ -z "$zip" ]; then
    info "Looking up the latest $ARK_REPO release" >&2
    url=$(gh_asset_url "$ARK_REPO" "$pattern" "$exclude" || true)
    [ -n "$url" ] || die "Couldn't find a release file matching '$pattern'. Download it from
  https://github.com/$ARK_REPO/releases into $DOWNLOADS and run again."
    zip="$DOWNLOADS/$(basename "$url")"
    info "Downloading $(basename "$url")" >&2
    curl -fL --retry 3 -o "$zip" "$url" >&2
  fi
  echo "$zip"
}

# Copy the PSP/ folder from a zip onto the Go's system storage.
ark_copy_zip() {
  local zip="$1" work="$DOWNLOADS/extracted" src
  rm -rf "$work"; mkdir -p "$work"
  unzip -q -o "$zip" -d "$work"
  src=$(find "$work" -maxdepth 3 -type d -name PSP | head -1)
  [ -n "$src" ] || die "No PSP folder inside $(basename "$zip")."
  rsync -rt "$src/" "$PSPGO_VOL/PSP/"
  ok "Copied $(basename "$zip") to the Go"
  ls "$PSPGO_VOL/PSP/GAME" | sed 's/^/    PSP\/GAME\//'
}

ark_stage() {
  fw_cleanup
  ark_copy_zip "$(ark_fetch 'FasterARK_psp(_lite)?\.zip$' 'full')"
  dev_tag
}

ark_update_stage() {
  ark_copy_zip "$(ark_fetch 'ARK_UPDATE.*\.zip$')"
  onpsp "Game > System Storage > ARK Updater. Or use OTA: ARK menu (SELECT) > Updates."
}

ark_instructions() {
  todo "start ARK-5 (about 1 minute)" \
    "If PSPGO/PSPGoSD are still in Finder's sidebar, eject them there." \
    "On the Go: press O to leave USB Connection." \
    "Go to Game > System Storage > FasterARK. Let it run; the Go restarts into ARK." \
    "Check: press SELECT on the home screen. The ARK menu should open." \
    "Don't run CustomIPL yet; that's the next step." \
    "Then Settings > USB Connection again, so I can check the files."
  say "  Until the CustomIPL step, ARK is temporary: after a full power-off, run FasterARK again."
}

cipl_instructions() {
  todo "make ARK permanent (about 1 minute)" \
    "If PSPGO/PSPGoSD are still in Finder's sidebar, eject them there." \
    "On the Go: press O to leave USB Connection. Battery over 75%, charger plugged in." \
    "Go to Game > System Storage > CustomIPL. Press X to install. Don't turn it off." \
    "Turn the Go fully off (hold the power switch up ~5 s), then on again." \
    "Check: System Information still mentions ARK. Then press Enter here."
}

# ARK keeps its settings in a text file on the Go, one per line: "always, NAME, on|off".
ark_settings_file() { echo "$PSPGO_VOL/PSP/SAVEDATA/ARK_01234/SETTINGS.TXT"; }

ark_setting_get() { # NAME -> on|off|"" (not listed)
  grep -E "^[^#]*, *$1 *," "$(ark_settings_file)" 2>/dev/null | tail -1 | sed 's/.*, *//' | tr -d ' \r'
}

ark_setting_set() { # NAME on|off
  local f; f=$(ark_settings_file)
  [ -f "$f" ] || die "No ARK settings file on the Go ($f). Is ARK installed?"
  cp "$f" "$f.bak"
  if grep -qE "^[^#]*, *$1 *," "$f"; then
    sed -E "s/^([^#]*, *$1 *, *).*/\1$2/" "$f.bak" > "$f"
  else
    printf 'always, %s, %s\n' "$1" "$2" >> "$f"
  fi
  ok "ARK setting $1 = $2"
}

# bash pspgo-setup.sh ark-settings [list | set NAME on|off]
ark_settings_cmd() {
  dev_require
  local f; f=$(ark_settings_file)
  [ -f "$f" ] || die "No ARK settings file on the Go ($f). Is ARK installed?"
  case "${1:-list}" in
    list) head1 "ARK settings (PSPGO/PSP/SAVEDATA/ARK_01234/SETTINGS.TXT)"; sed 's/^/  /' "$f" ;;
    set)  [ -n "${2:-}" ] && [ -n "${3:-}" ] || die "Usage: ark-settings set NAME on|off"
          ark_setting_set "$2" "$3"
          onpsp "Takes effect after a restart of the Go (or Restart VSH)." ;;
    *) die "Usage: bash pspgo-setup.sh ark-settings [list | set NAME on|off]" ;;
  esac
}

wpa2_instructions() {
  todo "join a WPA2 network" \
    "Router: a 2.4 GHz network with WPA2-AES (no TKIP, no WPA3 mixed). Split bands if 2.4/5 GHz share one name." \
    "On the Go: Settings > Network Settings > Infrastructure Mode > New Connection > Scan." \
    "Pick your network, choose WPA-PSK (AES) if it asks, type the password, Easy/automatic address." \
    "Test Connection at the end."
  say "  While WPA2 is on, WEP/WPA1 networks stop working. If it can't get an IP, set the IP manually."
}
