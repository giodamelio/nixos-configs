#!/usr/bin/env bash
# GATE 0.2 of the carbon rebuild — prove gallium still holds a complete copy of
# carbon's data. gallium is the ONLY copy (the old drive is dead), so this is
# strictly read-only: it observes via sudo and changes nothing.
set -uo pipefail

GAL="${1:-server@gallium.gio.ninja}"

echo "== datasets + snapshots under tank/rescue =="
ssh "$GAL" 'sudo zfs list -r -t all -o name,type,used,refer tank/rescue'

echo
echo "== incomplete receives (must be none) =="
ssh "$GAL" 'sudo zfs get -H -o name,value receive_resume_token -r tank/rescue' |
  awk '$2 != "-" {print "  INCOMPLETE: " $1; f=1} END {if (!f) print "  (none)"}'

echo
echo "== the four datasets must each carry @rescue-evac =="
snaps=$(ssh "$GAL" 'sudo zfs list -H -o name -t snapshot -r tank/rescue')
for d in carbon-root carbon-home carbon-vms carbon-microvms; do
  if printf '%s\n' "$snaps" | grep -qx "tank/rescue/$d@rescue-evac"; then
    echo "  ok      tank/rescue/$d@rescue-evac"
  else
    echo "  MISSING tank/rescue/$d@rescue-evac"
  fi
done

echo
echo "== sanity: measured 2026-07-30 - root 22.8G, home 3.47G, microvms 5.19M, vms ~300K =="
echo "   (tank/rescue total 26.3G; the uncompressed send sizes run ~1.9x higher)"

# The only copy of carbon's data must not be on a retention clock.
echo
echo "== anything set to auto-prune these? =="
ssh "$GAL" 'sudo zfs get -H -o name,value -r com.sun:auto-snapshot tank/rescue 2>/dev/null' |
  awk '$2 != "-" {print "  " $0; f=1} END {if (!f) print "  (no auto-snapshot property set)"}'

echo
echo "== gallium pool health + free space =="
ssh "$GAL" 'sudo zpool list -o name,size,alloc,free,capacity,health tank'
