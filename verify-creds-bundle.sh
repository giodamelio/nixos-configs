#!/usr/bin/env bash
# GATE 0.1 of the carbon rebuild — prove the secrets bundle opens and is complete.
# Lists only; no plaintext is ever written to disk. Prompts once for the bundle
# passphrase (password manager). Read-only, safe to re-run.
set -uo pipefail

here=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
BUNDLE="${1:-$here/tmp/carbon-creds-backup.tar.age}"
[ -f "$BUNDLE" ] || {
  echo "no bundle at $BUNDLE" >&2
  exit 1
}

# Everything carbon's credstore is expected to hold: the 39 fleet.secrets it
# holds (37 it provisions + garage-metrics-token and wg-nfs-pub-gallium received
# from gallium), plus three hand-wired blobs that are not fleet.secrets at all.
# Regenerate the fleet.secrets half with:
#   nix eval --json .#nixosConfigurations.carbon.config.systemd.paths \
#     --apply 'builtins.attrNames' | tr ',' '\n' | tr -d '[]"' | sed 's/^secret-//'
expected=$(
  cat <<'EOF'
caddy-cloudflare-api-token
consul-encrypt
credsync-push-key
eater-of-feeds-password
forgejo-oidc-client-id
forgejo-oidc-client-secret
forgejo-runner-env
garage-metrics-token
gradient-action-deploy-webhook-token
gradient-cache-netrc
gradient-cache-signing-key
gradient-crypt-secret
gradient-deployer-api-key
gradient-forgejo-access-token
gradient-forgejo-webhook-secret
gradient-github-app-private-key
gradient-github-app-webhook-secret
gradient-jwt-secret
gradient-metrics-token
gradient-oidc-client-secret
gradient-org-private-key
gradient-s3-secret-key
gradient-worker-peers
gradient-worker-token
grafana-secret-key
mealie-fastmail-smtp-password
mealie-oidc-client-id
mealie-oidc-client-secret
mealie-openai-api-key
miniflux-oauth2-client-id
miniflux-oauth2-client-secret
netdata-api-key
netdata-pushover-app-token
netdata-pushover-user-token
paperless-env
pocket-id-encryption-key
solidtime-app-key
unifi-controller-unpoller-password
wg-nfs-priv-carbon
wg-nfs-pub-carbon
wg-nfs-pub-gallium
zwavejs-secrets
EOF
)

echo "== decrypting $BUNDLE (passphrase prompt follows) =="
listing=$(age -d "$BUNDLE" | tar tv) || {
  echo "FAILED to decrypt or untar" >&2
  exit 1
}

echo
echo "== contents =="
printf '%s\n' "$listing"

# tar tv columns: perms owner size date time name
actual=$(printf '%s\n' "$listing" | awk '$NF != "./" {n=$NF; sub(/^\.\//,"",n); if (n != "") print n}' | sort -u)
empty=$(printf '%s\n' "$listing" | awk '$3 == 0 && $NF != "./" {print $NF}')

echo
echo "== zero-byte entries (must be none) =="
# shellcheck disable=SC2086 # deliberate split: one name per printf cycle
[ -n "$empty" ] && printf 'EMPTY: %s\n' $empty || echo "(none)"

echo
echo "== in bundle but not expected (orphans - fine, just note them) =="
comm -23 <(printf '%s\n' "$actual") <(printf '%s\n' "$expected" | sort) | sed 's/^/  + /' | grep . || echo "  (none)"

echo
echo "== EXPECTED BUT MISSING (each one is a secret you cannot recover) =="
comm -13 <(printf '%s\n' "$actual") <(printf '%s\n' "$expected" | sort) | sed 's/^/  - /' | grep . || echo "  (none)"

echo
echo "== the four that are unrecoverable if absent =="
for n in pocket-id-encryption-key solidtime-app-key grafana-secret-key paperless-env; do
  if printf '%s\n' "$actual" | grep -qx "$n"; then echo "  ok      $n"; else echo "  MISSING $n"; fi
done

echo
echo "counted $(printf '%s\n' "$actual" | grep -c .) entries, expected $(printf '%s\n' "$expected" | grep -c .)"
