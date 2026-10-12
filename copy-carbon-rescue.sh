#!/usr/bin/env bash
# Copy carbon's rescue datasets from gallium (tank/rescue) into carbon's bowl
# pool (bowl/rescue). gallium sends straight to carbon over the LAN, logging in
# with this machine's forwarded ssh agent. Read-only against gallium.
# Safe to re-run: datasets already copied (matching snapshot GUID) are skipped.
# shellcheck disable=SC2029 # remote commands are built locally on purpose
set -euo pipefail

GAL="${1:-server@gallium.gio.ninja}"
CARBON="${2:-server@carbon.gio.ninja}"
SNAP=rescue-evac

# dataset:extra `zfs send` flags:expected size for pv. -R brings
# carbon-vms/hammond + its history. Sizes are USED on gallium (2026-10-12),
# which tracks a compressed (-c) stream.
DATASETS=(
  "carbon-root::22.8G"
  "carbon-home::3.47G"
  "carbon-vms:-R:616K"
  "carbon-microvms::5.19M"
)
# Every dataset whose @rescue-evac GUID must match on both ends.
VERIFY=(carbon-root carbon-home carbon-vms carbon-vms/hammond carbon-microvms)

# pv runs on gallium, where the stream starts.
PV="$(ssh "$GAL" "nix build --no-link --print-out-paths nixpkgs#pv")/bin/pv"

guid() {
  ssh "$1" "sudo zfs get -H -o value guid $2@$SNAP 2>/dev/null" || true
}

if ! ssh "$CARBON" "sudo zfs list -H bowl/rescue >/dev/null 2>&1"; then
  ssh "$CARBON" "sudo zfs create -o mountpoint=none bowl/rescue"
fi

for entry in "${DATASETS[@]}"; do
  IFS=: read -r name flags size <<<"$entry"
  src_guid="$(guid "$GAL" "tank/rescue/$name")"
  if [ -z "$src_guid" ]; then
    echo "tank/rescue/$name@$SNAP not found on gallium" >&2
    exit 1
  fi

  dst_guid="$(guid "$CARBON" "bowl/rescue/$name")"
  if [ "$dst_guid" = "$src_guid" ]; then
    echo "skip $name (already copied)"
    continue
  fi
  if ssh "$CARBON" "sudo zfs list -H bowl/rescue/$name >/dev/null 2>&1"; then
    echo "bowl/rescue/$name exists but does not match gallium (partial copy?)." >&2
    echo "Destroy it and re-run: ssh $CARBON sudo zfs destroy -r bowl/rescue/$name" >&2
    exit 1
  fi

  echo "copy $name"
  # -c keeps blocks compressed in flight; -u and -x mountpoint keep the copies
  # unmounted (an -R stream would otherwise carry carbon-vms' old mountpoint).
  ssh -A -t "$GAL" "set -o pipefail;
    sudo zfs send -c $flags tank/rescue/$name@$SNAP |
    $PV -f -s $size -N $name |
    ssh -o StrictHostKeyChecking=accept-new $CARBON 'sudo zfs recv -u -x mountpoint bowl/rescue/$name'"
done

echo
failed=0
for d in "${VERIFY[@]}"; do
  a="$(guid "$GAL" "tank/rescue/$d")"
  b="$(guid "$CARBON" "bowl/rescue/$d")"
  if [ -n "$a" ] && [ "$a" = "$b" ]; then
    echo "ok   $d"
  else
    echo "DIFF $d  gallium=$a carbon=$b"
    failed=1
  fi
done

if [ "$failed" -ne 0 ]; then
  echo "verification failed; bowl/rescue left writable" >&2
  exit 1
fi

ssh "$CARBON" "sudo zfs set readonly=on bowl/rescue"
echo
ssh "$CARBON" "sudo zfs list -r -o name,used,refer,mountpoint,readonly bowl/rescue"
echo
echo "carbon now holds a verified copy. Keep gallium's tank/rescue until carbon"
echo "has its own working, restore-tested backup (NIXOS-52)."
