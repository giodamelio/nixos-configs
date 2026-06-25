#!/usr/bin/env bash
# Pre-deploy ZFS snapshot for carbon. Run from your workstation before the
# den-migration deploy. Recursive snapshot of the `tank` pool (root + service
# data: postgres DBs, home-assistant/zwave state, etc.). Snapshots are instant
# (CoW); this is an extra named checkpoint on top of the sanoid schedule.

# TAG is intentionally expanded client-side so the remote snapshots get the
# timestamp computed here.
# shellcheck disable=SC2029
set -euo pipefail

HOST=server@carbon.gio.ninja
TAG="pre-den-migration-$(date +%Y%m%d-%H%M%S)"

echo ">> carbon snapshot tag: $TAG"
ssh "$HOST" "sudo zfs snapshot -r tank@$TAG"

echo ">> verifying:"
ssh "$HOST" "zfs list -t snapshot -r tank | grep '$TAG'"

cat <<EOF

Done. To roll carbon back to this checkpoint (per dataset):
  ssh $HOST "sudo zfs rollback -r tank@$TAG"
  ssh $HOST "sudo zfs rollback -r tank/root@$TAG"   # etc. for each child dataset
EOF
