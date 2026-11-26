# Official Sony firmware 6.61 for PSP Go.

FW_FILE_NAME="661GO_EBOOT.PBP"

fw_download() {
  local f="$DOWNLOADS/$FW_FILE_NAME"
  if [ ! -s "$f" ]; then
    info "Downloading Sony's PSP Go 6.61 update"
    curl -fL --retry 3 -o "$f.part" "$FW_URL" && mv "$f.part" "$f" || {
      rm -f "$f.part"
      die "Sony download failed. Download the PSP Go 6.61 EBOOT.PBP from
  https://consolemods.org/wiki/PSP:Updating_your_Firmware_(OFW)
and save it as $f, then run this again."
    }
  fi
  [ "$(filesize "$f")" -gt 10000000 ] || die "$f looks too small. Delete it and run again."
  ok "Have $FW_FILE_NAME ($(human "$(filesize "$f")"))"
}

fw_stage() {
  fw_download
  mkdir -p "$PSPGO_VOL/PSP/GAME/UPDATE"
  cp "$DOWNLOADS/$FW_FILE_NAME" "$PSPGO_VOL/PSP/GAME/UPDATE/EBOOT.PBP"
  ok "Staged at PSP/GAME/UPDATE/EBOOT.PBP on the Go"
}

fw_cleanup() {
  if [ -f "$PSPGO_VOL/PSP/GAME/UPDATE/EBOOT.PBP" ]; then
    rm -f "$PSPGO_VOL/PSP/GAME/UPDATE/EBOOT.PBP"
    rmdir "$PSPGO_VOL/PSP/GAME/UPDATE" 2>/dev/null || true
    ok "Removed the used update file"
  fi
}

fw_instructions() {
  onpsp "Plug in the charger and keep it plugged in."
  onpsp "Game > System Storage > PSP Update ver 6.61 > follow the prompts. Don't power off."
  onpsp "When it restarts: Settings > System Settings > System Information should say 6.61."
}
