#!/usr/bin/env bash
# Pull the Phase 8 pre-install checks forward: mount carbon's rescued root
# READ-ONLY on gallium and inspect it, before committing to the rebuild work.
#
# Safe by construction: ZFS snapshots are immutable, so the mount cannot write.
# It mounts, reads, and unmounts. gallium holds the only copy of this data, so
# nothing here creates, destroys, clones, or sets a property.
set -uo pipefail

GAL="${1:-server@gallium.gio.ninja}"
SNAP=tank/rescue/carbon-root@rescue-evac
MNT=/mnt/carbon-rescue-peek

# The host key the flake expects (modules/hosts/carbon/default.nix).
EXPECT_HOSTKEY="ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIX5P0ZXB1SUbiDrm42t19GEsz80dw+yI0GoO0tYlJsn"

# shellcheck disable=SC2087 # unquoted on purpose: $MNT/$SNAP expand here, \$d expands remotely
ssh "$GAL" "sudo bash -s" <<EOF
set -uo pipefail
trap 'sudo umount $MNT 2>/dev/null; sudo rmdir $MNT 2>/dev/null' EXIT

install -d -m 0700 $MNT
if ! mount -t zfs -o ro $SNAP $MNT 2>/dev/null; then
  echo "FAILED to mount $SNAP read-only" >&2
  exit 1
fi
echo "mounted $SNAP read-only at $MNT"

echo
echo "== postgres: which major actually holds the data? =="
echo "   (the new build wants 17; older dirs are upgrade leftovers)"
for v in $MNT/var/lib/postgresql/*/; do
  [ -d "\$v" ] || continue
  maj=\$(basename "\$v")
  ver=\$(cat "\$v/PG_VERSION" 2>/dev/null || echo "?")
  size=\$(timeout 60 du -sh "\$v" 2>/dev/null | cut -f1 || echo "timeout")
  dbs=\$(find "\$v/base" -maxdepth 1 -mindepth 1 -type d 2>/dev/null | wc -l)
  mtime=\$(stat -c %y "\$v" 2>/dev/null | cut -d. -f1)
  printf '  %-4s PG_VERSION=%-4s size=%-7s dirs-in-base=%-4s mtime=%s\n' \
    "\$maj" "\$ver" "\$size" "\$dbs" "\$mtime"
done

echo
echo "== which cluster was RUNNING when the snapshot was taken? =="
echo "   (postmaster.pid only exists in the live one - the snapshot caught it hot)"
for v in $MNT/var/lib/postgresql/*/; do
  [ -d "\$v" ] || continue
  maj=\$(basename "\$v")
  if [ -e "\$v/postmaster.pid" ]; then echo "  LIVE    \$maj"; else echo "  stopped \$maj"; fi
done

echo
echo "== ssh host key =="
cat $MNT/etc/ssh/ssh_host_ed25519_key.pub 2>/dev/null || echo "  NO host key"

echo
echo "== machine-id =="
cat $MNT/etc/machine-id 2>/dev/null || echo "  NO machine-id"

echo
echo "== systemd credential secret (needed to decrypt the old credstore) =="
ls -l $MNT/var/lib/systemd/credential.secret 2>/dev/null || echo "  ABSENT"

echo
echo "== uid/gid maps (keep nfs-* ownership stable) =="
ls -l $MNT/var/lib/nixos/uid-map $MNT/var/lib/nixos/gid-map 2>/dev/null || echo "  ABSENT"

echo
echo "== credstore blobs (cross-check against the age bundle) =="
ls $MNT/usr/lib/credstore.encrypted/ 2>/dev/null | sort || echo "  NO credstore"

echo
echo "== service state dirs (DynamicUser services live under private/) =="
for d in openbao containers hass grafana forgejo postgresql redis; do
  if [ -e "$MNT/var/lib/\$d" ]; then echo "  ok      /var/lib/\$d"; else echo "  absent  /var/lib/\$d"; fi
done

echo
echo "== /var/lib/private (DynamicUser state: paperless, mealie, miniflux, ...) =="
ls $MNT/var/lib/private/ 2>/dev/null || echo "  ABSENT"
EOF

echo
echo "== compare the host key above against what the flake expects =="
echo "  $EXPECT_HOSTKEY"
