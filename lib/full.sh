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
  dev_eject_all; dev_wait_gone
  fw_instructions
  info "Waiting for the Go to come back after the update (open USB Connection again when it's done)."
  dev_wait
  confirm "Does System Information now say 6.61?" y || die "Update didn't finish. Run 'bash pspgo-setup.sh full' to try again."
  fw_cleanup
  state_set firmware done
}

step_ark() {
  dev_require
  ark_stage
  dev_eject_all; dev_wait_gone
  ark_instructions
  info "Waiting for the Go to come back (open USB Connection again after you've seen the ARK menu)."
  dev_wait
  if ark_present; then ok "ARK files detected on the Go."; fi
  confirm "Did pressing SELECT show the ARK menu?" y || die "ARK didn't start. Re-run FasterARK on the Go, then: bash pspgo-setup.sh full"
  state_set ark done
}

step_cipl() {
  say "Making ARK permanent (survives power-off). Recommended after a short test."
  if confirm "Do it now?" y; then
    dev_eject_all
    cipl_instructions
    pause "Press Enter when the Go has restarted with ARK."
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
  dev_eject_all
  wpa2_instructions
  local r
  r=$(choose "Was a WPA2 option in Custom Firmware Settings?" "Yes, turned it on" "Not there" "Skip for now")
  state_set wpa2_result "$r"
  state_set wpa2 done
}

step_profile() {
  dev_wait
  sync_push
  state_set profile done
}

step_autosync() {
  if is_mac && confirm "Push profile/ automatically whenever the Go is plugged in?" y; then
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
