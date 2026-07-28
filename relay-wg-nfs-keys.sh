#!/usr/bin/env bash
# One-shot bootstrap: relay each host's wg-nfs public key to its peer via this
# machine, since carbon and gallium can't SSH each other to run the normal
# credsync push. Run from a machine with root SSH to both hosts.
set -euo pipefail

CREDSYNC=/nix/store/5phnw97wwl5xgcnz7dfbzyfaanx5dxfl-credsync/bin/credsync
STORE=/usr/lib/credstore.encrypted

# relay <secret-name> <origin-host> <dest-host>
relay() {
  echo ">> $1: $2 -> $3"
  ssh "server@$2" "sudo systemd-creds decrypt --name=$1 $STORE/$1 -" \
    | ssh "server@$3" "sudo $CREDSYNC write $1 wg-nfs.service"
}

relay wg-nfs-pub-carbon  carbon.gio.ninja  gallium.gio.ninja
relay wg-nfs-pub-gallium gallium.gio.ninja carbon.gio.ninja
