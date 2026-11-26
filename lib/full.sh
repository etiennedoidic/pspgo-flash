# Guided first-time setup. Resumable: finished steps are skipped on re-run.
#   bash pspgo-setup.sh full            continue where you left off
#   bash pspgo-setup.sh full --reset    start over (backups are kept)
#   bash pspgo-setup.sh full --from ark redo from a step

FULL_STEPS="preflight backup firmware ark cipl wpa2 profile autosync"

full_setup() {
  case "${1:-}" in
    --reset) : > "$STATE_FILE"; ok "Setup progress cleared." ;;
    --from)
      [ -n "${2:-}" ] || die "Usage: full --from STEP  ($FULL_STEPS)"
      local s clear=""
      for s in $FULL_STEPS; do [ "$s" = "$2" ] && clear=1; [ -n "$clear" ] && state_set "$s" ""; done ;;
  esac

  say ""
  say "${B}PSP Go setup${N}: official 6.61 -> ARK-5 custom firmware -> your profile -> auto-push."
  say "Each step tells you exactly what to press on the Go. Safe to quit (Ctrl-C) and re-run."
  say ""
  say "  The whole path, so nothing is a surprise:"
  say "    1. Back up the Go to this Mac"
  say "    2. Update to Sony's 6.61   (on the Go: Game > System Storage > PSP Update)"
  say "    3. Start ARK               (on the Go: Game > System Storage > FasterARK)   temporary until step 4"
  say "    4. Make ARK permanent      (on the Go: Game > System Storage > CustomIPL)"
  say "    5. Turn on WPA2 Wi-Fi, push your profile, turn on auto-push"
  say "  Between steps the Go goes back and forth between USB Connection and the home screen."

  local s n=1 total
  total=$(echo $FULL_STEPS | wc -w | tr -d ' ')
  for s in $FULL_STEPS; do
    if state_done "$s"; then ok "[$n/$total] $s (done)"; else
      head1 "[$n/$total] $s"
      "step_$s"
    fi
    n=$((n+1))
  done
  state_set setup done
  full_summary
}

step_preflight() {
  is_mac || warn "This is built for macOS. Some steps (eject, autosync, wallpaper resize) need it."
  need_cmds curl rsync unzip
  is_mac && need_cmds diskutil
  dev_wait
  dev_tag
  ok "Found PSPGO$(sd_mounted && echo ' and PSPGoSD')."
  state_set preflight done
}

step_backup() {
  dev_require
  dev_backup
  state_set backup done
}

step_firmware() {
  local v
  v=$(choose "On the Go: Settings > System Settings > System Information. What does System Software say?" \
      "Below 6.61 (e.g. 6.39)" "6.61" "Already shows ARK")
  case "$v" in
    "6.61") state_set firmware done; ok "Already on 6.61."; return ;;
    "Already shows ARK") state_set firmware done; state_set ark done; ok "ARK already installed."; return ;;
  esac
  dev_require
  fw_stage
  dev_eject_all
  fw_instructions
  dev_wait_gone
  DEV_WAIT_QUIET=1 dev_wait
  confirm "Does System Information now say 6.61?" y || die "Update didn't finish. Run 'bash pspgo-setup.sh full' to try again."
  fw_cleanup
  state_set firmware done
}

step_ark() {
  dev_require
  ark_stage
  dev_eject_all
  ark_instructions
  dev_wait_gone
  DEV_WAIT_QUIET=1 dev_wait
  if ark_present; then ok "ARK files detected on the Go."; fi
  confirm "Did ARK start? (pressing SELECT on the home screen opens the ARK menu)" y || die "ARK didn't start. Re-run FasterARK on the Go, then: bash pspgo-setup.sh full"
  ok "ARK is running, but only until the next full power-off. Next step makes it permanent."
  state_set ark done
}

step_cipl() {
  say "Right now ARK is temporary: a full power-off brings back plain 6.61 until you run FasterARK again."
  say "CustomIPL fixes that: it makes the Go boot straight into ARK, every time."
  if confirm "Make ARK permanent now?" y; then
    dev_eject_all
    cipl_instructions
    pause "Press Enter when it has restarted and still shows ARK."
    state_set cipl done
  else
    state_set cipl_result later
    warn "Skipped. ARK stays temporary. Re-run later with: bash pspgo-setup.sh full --from cipl"
    state_set cipl done
    return
  fi
  state_set cipl_result installed
}

step_wpa2() {
  # ARK-5 has no on-screen switch for this: it's a line in SETTINGS.TXT on the Go.
  dev_wait
  local cur; cur=$(ark_setting_get wpa2)
  if [ "$cur" = on ]; then ok "WPA2 is already on in ARK's settings."
  else
    ark_setting_set wpa2 on
    onpsp "Restart the Go after this run so WPA2 takes effect."
  fi
  state_set wpa2_result "on (SETTINGS.TXT)"
  wpa2_instructions
  say "  You can do the Wi-Fi part any time later; the script carries on now."
  state_set wpa2 done
}

step_profile() {
  dev_wait
  sync_push
  state_set profile done
}

step_autosync() {
  say "profile/ in this folder is your Go's setup kept on the Mac: themes, wallpapers, plugins,"
  say "homebrew apps, music/videos/pictures, and saved Wi-Fi networks. 'push' copies it onto the Go."
  say ""
  say "Auto-push does that for you: whenever you open USB Connection on the Go, the Mac copies"
  say "anything new or changed in profile/ onto it, then ejects it and shows a notification."
  say "Handy if you add music or themes on the Mac: plug in, wait for the notification, done."
  say "It only adds/updates files (never deletes from the Go), and ignores other USB drives."
  say "Skip it if you'd rather push by hand (bash pspgo-setup.sh push). Change later: autosync on|off."
  if is_mac && confirm "Turn on auto-push?" y; then
    state_set setup done
    autosync_cmd on
  fi
  state_set autosync done
}

full_summary() {
  head1 "Setup complete"
  say "  WPA2: $(state_get wpa2_result)"
  say ""
  say "  Everyday commands:"
  say "    bash pspgo-setup.sh status            what's connected"
  say "    bash pspgo-setup.sh push              send profile/ to the Go"
  say "    bash pspgo-setup.sh games add X.iso   add to library/, then: games push"
  say "    bash pspgo-setup.sh studio            themes, wallpapers, wifi in the browser"
  say "    bash pspgo-setup.sh ark-update        newer ARK"
  dev_eject_all
}
