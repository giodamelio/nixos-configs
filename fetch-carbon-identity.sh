#!/usr/bin/env bash
# Stage carbon's identity (ssh host keys, machine-id, /var/lib/nixos uid/gid
# maps) from gallium's rescue snapshot into a directory for
# `nixos-anywhere --extra-files`. Read-only against gallium: the snapshot is
# mounted ro and only read.
set -euo pipefail

OUT="${1:-$(mktemp -d -t carbon-identity.XXXXXX)}"
GAL="${2:-server@gallium.gio.ninja}"
SNAP=tank/rescue/carbon-root@rescue-evac

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EXPECT_HOSTKEY="$(sed -n 's/^ *ssh\.hostKey = "\(.*\)";/\1/p' "$REPO/modules/hosts/carbon/default.nix")"
if [ -z "$EXPECT_HOSTKEY" ]; then
  echo "could not read ssh.hostKey from modules/hosts/carbon/default.nix" >&2
  exit 1
fi

if [ -e "$OUT" ] && [ -n "$(ls -A "$OUT")" ]; then
  echo "$OUT is not empty; refusing to mix identities" >&2
  exit 1
fi
install -d -m 0700 "$OUT"

# shellcheck disable=SC2087 # unquoted on purpose: $SNAP expands here, \$MNT expands remotely
ssh "$GAL" "sudo bash -s" <<EOF | tar -xpf - -C "$OUT"
set -euo pipefail
MNT=\$(mktemp -d)
trap 'umount "\$MNT"; rmdir "\$MNT"' EXIT
mount -t zfs -o ro $SNAP "\$MNT"
tar -C "\$MNT" -cpf - \
  etc/ssh/ssh_host_ed25519_key etc/ssh/ssh_host_ed25519_key.pub \
  etc/ssh/ssh_host_rsa_key etc/ssh/ssh_host_rsa_key.pub \
  etc/machine-id \
  var/lib/nixos
EOF

GOT_HOSTKEY="$(cut -d' ' -f1-2 "$OUT/etc/ssh/ssh_host_ed25519_key.pub")"
if [ "$GOT_HOSTKEY" != "$EXPECT_HOSTKEY" ]; then
  echo "host key mismatch" >&2
  echo "  flake:    $EXPECT_HOSTKEY" >&2
  echo "  snapshot: $GOT_HOSTKEY" >&2
  exit 1
fi

for f in etc/machine-id var/lib/nixos/uid-map var/lib/nixos/gid-map; do
  if [ ! -s "$OUT/$f" ]; then
    echo "missing or empty: $f" >&2
    exit 1
  fi
done

echo "carbon identity staged in $OUT (host key matches the flake)"
find "$OUT" -type f -printf '  %M  %p\n'
echo
echo "Delete it after the install; it holds carbon's private host keys."
echo
echo "nix run github:nix-community/nixos-anywhere -- \\"
echo "  --flake .#carbon \\"
echo "  --target-host nixos@<installer-ip> \\"
echo "  --phases disko,install \\"
echo "  --build-on local \\"
echo "  --extra-files $OUT"
