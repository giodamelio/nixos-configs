#!/usr/bin/env bash
# Evacuate carbon's frozen tank@rescue-evac datasets to gallium, with a live pv
# progress bar (%, rate, ETA) on each. Run from INSIDE carbon, in tmux.
# `zfs recv -s` keeps partials, so a broken send RESUMES (see bottom) — never
# lose progress by restarting.
#
# NOTE: root is probably still sending in another terminal. Leave its line
# commented and just run home/vms/microvms after it finishes. Only uncomment
# root if you stopped that send — it will resume from the -s partial, not restart.
set -uo pipefail

GAL="ssh server@gallium.gio.ninja"

evac() {  # evac <dest-name> <source-snapshot> [extra zfs send flags...]
  local dst="tank/rescue/$1" src="$2"; shift 2
  local size pvargs=()
  size=$(sudo zfs send -nP "$@" "$src" 2>/dev/null | awk '/^size/{print $2; exit}')
  [ -n "${size:-}" ] && pvargs=(-s "$size")
  echo ">>> $src  ->  $dst   (~$(numfmt --to=iec "${size:-0}"))"
  sudo zfs send "$@" "$src" | pv "${pvargs[@]}" | $GAL "sudo zfs recv -s -u $dst"
}

# evac carbon-root     tank/root@rescue-evac            # already running elsewhere
evac carbon-home     tank/home@rescue-evac
evac carbon-vms      tank/vms@rescue-evac      -R
evac carbon-microvms tank/microvms@rescue-evac

# RESUME a broken/stopped transfer (example: root):
#   TOK=$($GAL 'sudo zfs get -H -o value receive_resume_token tank/rescue/carbon-root')
#   sudo zfs send -t "$TOK" | pv | $GAL 'sudo zfs recv -s tank/rescue/carbon-root'
