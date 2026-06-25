#!/usr/bin/env bash
# Pre-deploy ZFS snapshot for gallium. Run from your workstation before the
# den-migration deploy. Recursive snapshot of BOTH pools:
#   tank  — service + NFS data (forgejo, paperless exported to carbon, garage,
#           attic, immich, syncthing, ...)
#   boot  — system root
# Snapshots are instant (CoW); an extra named checkpoint on top of sanoid.

# TAG is intentionally expanded client-side so the remote snapshots get the
# timestamp computed here.
# shellcheck disable=SC2029
set -euo pipefail

HOST=server@gallium.gio.ninja
TAG="pre-den-migration-$(date +%Y%m%d-%H%M%S)"

echo ">> gallium snapshot tag: $TAG"
ssh "$HOST" "sudo zfs snapshot -r tank@$TAG"
ssh "$HOST" "sudo zfs snapshot -r boot@$TAG"

echo ">> verifying:"
ssh "$HOST" "zfs list -t snapshot -r tank | grep '$TAG'"
ssh "$HOST" "zfs list -t snapshot -r boot | grep '$TAG'"

cat <<EOF

Done. To roll gallium back to this checkpoint (per dataset):
  ssh $HOST "sudo zfs rollback -r tank@$TAG"      # and each tank/* child
  ssh $HOST "sudo zfs rollback -r boot@$TAG"      # and each boot/* child
EOF
