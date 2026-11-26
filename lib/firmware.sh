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
  todo "update the Go to 6.61 (about 5 minutes)" \
    "If PSPGO/PSPGoSD are still in Finder's sidebar, eject them there." \
    "On the Go: press O to leave USB Connection. Plug in the charger." \
    "Go to Game > System Storage > PSP Update ver 6.61. Follow the prompts. Don't turn it off." \
    "When it has restarted: Settings > USB Connection again, so I can check it."
  say "  If the updater says the data is for another system, the file isn't the Go one. Either delete"
  say "  downloads/$FW_FILE_NAME and put the PSP Go 6.61 EBOOT.PBP from consolemods.org there, or update"
  say "  over Wi-Fi: Settings > System Update > Update via Internet (needs a WEP/WPA/open network on stock firmware)."
}
