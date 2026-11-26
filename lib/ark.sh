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
  ark_copy_zip "$(ark_fetch 'FasterARK_psp.*\.zip$' 'full')"
  dev_tag
}

ark_update_stage() {
  ark_copy_zip "$(ark_fetch 'ARK_UPDATE.*\.zip$')"
  onpsp "Game > System Storage > ARK Updater. Or use OTA: ARK menu (SELECT) > Updates."
}

ark_instructions() {
  onpsp "Game > System Storage > FasterARK. The Go restarts into ARK."
  onpsp "Press SELECT on the home screen. The ARK menu should appear."
  onpsp "Until the CustomIPL step, ARK is temporary: after a full power-off, launch FasterARK again."
}

cipl_instructions() {
  onpsp "Battery over 75% and charger plugged in."
  onpsp "Game > System Storage > CustomIPL (cIPL Flasher) > press X to install."
  onpsp "After restart: System Information > System Software should mention ARK."
}

wpa2_instructions() {
  onpsp "XMB: Settings > Custom Firmware Settings (or ARK menu > Extras > Custom Firmware Settings). Turn on WPA2, then Restart VSH."
  onpsp "Router: a 2.4 GHz network, WPA2 with AES only (TKIP doesn't work). Split bands if 2.4/5 GHz share one name."
  onpsp "WPA2/WPA3 mixed mode often fails to get an IP: set the IP address manually in the PSP's network settings."
  onpsp "While WPA2 is on, WEP and WPA1 networks stop working."
}
