#!/usr/bin/env bash
# Load carbon's secrets from the passphrase-encrypted credstore bundle into the
# agevault vault (tmp/secrets). Plaintext only ever lives in a mode-700 tmpfs dir,
# wiped on exit. Validates the whole bundle before writing anything and refuses
# to overwrite an existing vault secret without --force.
#
# Usage: import-carbon-creds.sh [--dry-run] [--force] [bundle]
set -euo pipefail

here=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)

dry_run=0
force=0
bundle="$here/tmp/carbon-creds-backup.tar.age"
for arg in "$@"; do
  case "$arg" in
  --dry-run) dry_run=1 ;;
  --force) force=1 ;;
  -*)
    echo "unknown flag: $arg" >&2
    exit 1
    ;;
  *) bundle="$arg" ;;
  esac
done

VAULT="${AGEVAULT_ROOT:-$here/tmp/secrets}"
HOST=carbon

# old_blob:vault_name:scope. The hyphenated blob is the live value (MIGRATION.md
# "Pick the live blob, not its twin"). scope=common stores the value once in
# common/ and symlinks it from hosts/carbon; gallium gets linked at its cutover.
# Gradient entries use gradient's hardcoded credential ids, because a named blob
# only loads under its embedded name. agevault rejects dashes, so the four ids
# that contain them (forgejo-inbound/-outbound, deploy-webhook, the worker UUID)
# are stored with dashes turned into underscores.
MAP=(
  "caddy-cloudflare-api-token:caddy_cloudflare_api_token:carbon"
  "consul-encrypt:consul_encrypt:common"
  "eater-of-feeds-password:eater_of_feeds_password:carbon"
  "forgejo-oidc-client-id:forgejo_oidc_client_id:carbon"
  "forgejo-oidc-client-secret:forgejo_oidc_client_secret:carbon"
  "forgejo-runner-env:forgejo_runner_env:carbon"
  "garage-metrics-token:garage_metrics_token:common"
  "gradient-action-deploy-webhook-token:gradient_action_deploy_webhook_token:carbon"
  "gradient-cache-netrc:gradient_cache_netrc:carbon"
  "gradient-cache-signing-key:gradient_cache_main_signing_key:carbon"
  "gradient-crypt-secret:gradient_crypt_secret:carbon"
  "gradient-deployer-api-key:gradient_deployer_api_key:carbon"
  "gradient-forgejo-access-token:gradient_integration_forgejo_outbound_token:carbon"
  "gradient-forgejo-webhook-secret:gradient_integration_forgejo_inbound_secret:carbon"
  "gradient-github-app-private-key:gradient_github_app_private_key:carbon"
  "gradient-github-app-webhook-secret:gradient_github_app_webhook_secret:carbon"
  "gradient-jwt-secret:gradient_jwt_secret:carbon"
  "gradient-metrics-token:gradient_metrics_token:carbon"
  "gradient-oidc-client-secret:gradient_oidc_client_secret:carbon"
  "gradient-org-private-key:gradient_org_default_private_key:carbon"
  "gradient-s3-secret-key:gradient_s3_secret_access_key:carbon"
  "gradient-worker-peers:gradient_worker_peers:carbon"
  "gradient-worker-token:gradient_worker_4f7f7bfb_6013_405a_9a5f_fc98449725d7_token:carbon"
  "grafana-secret-key:grafana_secret_key:carbon"
  "mealie-fastmail-smtp-password:mealie_fastmail_smtp_password:carbon"
  "mealie-oidc-client-id:mealie_oidc_client_id:carbon"
  "mealie-oidc-client-secret:mealie_oidc_client_secret:carbon"
  "mealie-openai-api-key:mealie_openai_api_key:carbon"
  "miniflux-oauth2-client-id:miniflux_oauth2_client_id:carbon"
  "miniflux-oauth2-client-secret:miniflux_oauth2_client_secret:carbon"
  "netdata-api-key:netdata_api_key:carbon"
  "netdata-pushover-app-token:netdata_pushover_app_token:carbon"
  "netdata-pushover-user-token:netdata_pushover_user_token:carbon"
  "paperless-env:paperless_env:carbon"
  "pocket-id-encryption-key:pocket_id_encryption_key:carbon"
  "solidtime-app-key:solidtime_app_key:carbon"
  "syncoid-ssh-key:syncoid_ssh_key:carbon"
  "unifi-controller-unpoller-password:unifi_controller_unpoller_password:carbon"
  "wg-nfs-priv-carbon:wg_nfs_priv_carbon:carbon"
  "wg-nfs-pub-carbon:wg_nfs_pub_carbon:common"
  "wg-nfs-pub-gallium:wg_nfs_pub_gallium:common"
  "zwavejs-secrets:zwavejs_secrets:carbon"
)

# Stale underscore/.json twins of live blobs (importing one silently restores an
# old value), retired orphans, and credsync-push-key (dies with credsync).
SKIP=(
  gradient_org_default_private_key
  gradient_cache_main_signing_key
  secrets.json
  gradient_jwt_secret
  gradient_crypt_secret
  gradient_metrics_token
  gradient_integration_forgejo-outbound_token
  consul-encrypt.json
  # More pre-fleet.secrets underscore twins (not in MIGRATION.md's table); each
  # hyphenated counterpart is in MAP and is the blob carbon actually loaded.
  garage_metrics_token
  gradient_action_deploy-webhook_token
  gradient_deployer_api_key
  gradient_github_app_private_key
  gradient_github_app_webhook_secret
  gradient_integration_forgejo-inbound_secret
  gradient_oidc_client_secret
  gradient_s3_secret_access_key
  gradient_worker_4f7f7bfb-6013-405a-9a5f-fc98449725d7_token
  gradient_worker_peers
  apiToken
  attic-apps-cache-config
  caddy-cloudflare-config
  ca-password
  intermediate_ca_key
  cronitor-api-key
  discord_token
  forgejo-runner-token
  forgejo-runner-build-env
  hammond_openrouter_api_key
  mealie_token
  paperless-config
  telegraf-postgres-passfile
  test-secret
  wg-nfs-private-key
  wireguard-wg0-private-key
  credsync-push-key
)

die() {
  echo "ERROR: $*" >&2
  exit 1
}

[ -f "$VAULT/recipients.txt" ] || die "no vault at $VAULT (missing recipients.txt)"
command -v age >/dev/null || die "age not on PATH"

for row in "${MAP[@]}"; do
  IFS=: read -r _ name scope <<<"$row"
  [[ "$name" =~ ^[a-zA-Z0-9._]+$ ]] || die "invalid vault name in MAP: $name"
  [[ "$scope" == carbon || "$scope" == common ]] || die "invalid scope in MAP: $row"
done

tmpfs_base=/run/user/$UID
[ -d "$tmpfs_base" ] || tmpfs_base=/dev/shm
[ "$(stat -f -c %T "$tmpfs_base")" = tmpfs ] || die "$tmpfs_base is not tmpfs; refusing to write plaintext there"
WORK=$(mktemp -d "$tmpfs_base/carbon-creds.XXXXXX")
trap 'rm -rf "$WORK"' EXIT
chmod 700 "$WORK"

# CARBON_CREDS_TAR feeds an already-plain tar, so the logic can be tested
# without the interactive passphrase prompt.
if [ -n "${CARBON_CREDS_TAR:-}" ]; then
  echo "== reading plain tar $CARBON_CREDS_TAR (test mode) =="
  tar -x -C "$WORK" -f "$CARBON_CREDS_TAR"
else
  [ -f "$bundle" ] || die "no bundle at $bundle"
  echo "== decrypting $bundle into $WORK (passphrase prompt follows) =="
  age -d "$bundle" | tar -x -C "$WORK"
fi

missing=()
for row in "${MAP[@]}"; do
  IFS=: read -r old _ _ <<<"$row"
  [ -s "$WORK/$old" ] || missing+=("$old")
done
if [ "${#missing[@]}" -gt 0 ]; then
  printf '  missing or empty: %s\n' "${missing[@]}" >&2
  die "${#missing[@]} mapped blob(s) missing from the bundle; nothing written"
fi

known=$(
  for row in "${MAP[@]}"; do printf '%s\n' "${row%%:*}"; done
  printf '%s\n' "${SKIP[@]}"
)
unaccounted=$(comm -23 <(find "$WORK" -mindepth 1 -printf '%P\n' | sort) <(printf '%s\n' "$known" | sort))
if [ -n "$unaccounted" ]; then
  printf '%s\n' "$unaccounted" | sed 's/^/  unaccounted: /' >&2
  die "bundle has entries in neither MAP nor SKIP; classify them in this script first"
fi

existing=()
for row in "${MAP[@]}"; do
  IFS=: read -r _ name scope <<<"$row"
  host_path="$VAULT/hosts/$HOST/$name.age"
  if [ -e "$host_path" ] || [ -L "$host_path" ]; then existing+=("hosts/$HOST/$name.age"); fi
  if [ "$scope" = common ] && [ -e "$VAULT/common/$name.age" ]; then existing+=("common/$name.age"); fi
done
if [ "${#existing[@]}" -gt 0 ] && [ "$force" -eq 0 ]; then
  printf '  exists: %s\n' "${existing[@]}" >&2
  die "${#existing[@]} vault secret(s) already exist; re-run with --force to overwrite"
fi

echo
echo "== mapping (${#MAP[@]} to import, ${#SKIP[@]} known skips) =="
for row in "${MAP[@]}"; do
  IFS=: read -r old name scope <<<"$row"
  printf '  %-36s -> %-58s %-6s %5s B\n' "$old" "$name" "$scope" "$(stat -c %s "$WORK/$old")"
done
echo "skipped (present in bundle):"
for s in "${SKIP[@]}"; do
  if [ -e "$WORK/$s" ]; then printf '  %s\n' "$s"; fi
done

if [ "$dry_run" -eq 1 ]; then
  echo
  echo "dry run: nothing written"
  exit 0
fi

echo "== building agevault =="
AGEVAULT="$(nix build --no-link --print-out-paths "$here#agevault")/bin/agevault"
[ -x "$AGEVAULT" ] || die "agevault build did not produce $AGEVAULT"

export AGEVAULT_ROOT="$VAULT"
cd "$VAULT"

echo
echo "== writing to $VAULT =="
for row in "${MAP[@]}"; do
  IFS=: read -r old name scope <<<"$row"
  host_path="hosts/$HOST/$name.age"
  common_path="common/$name.age"
  if [ "$scope" = carbon ]; then
    "$AGEVAULT" write "$HOST" "$name" - <"$WORK/$old" >/dev/null
  elif [ -e "$common_path" ]; then
    # agevault write resolves the symlink, so this updates common/ in place.
    ln -sfn "../../$common_path" "$host_path"
    "$AGEVAULT" write "$HOST" "$name" - <"$WORK/$old" >/dev/null
  else
    # agevault cannot write to common/ directly: write under the host, then move
    # it into common/ and link it back.
    rm -f "$host_path"
    "$AGEVAULT" write "$HOST" "$name" - <"$WORK/$old" >/dev/null
    mv "$host_path" "$common_path"
    ln -s "../../$common_path" "$host_path"
  fi
  printf '  wrote %s/%s%s\n' "$HOST" "$name" "$([ "$scope" = common ] && echo " (-> common)")"
done

"$AGEVAULT" generate-toml

manifest="${AGEVAULT_MANIFEST:-$(sed -n 's/^manifest_path *= *"\(.*\)"/\1/p' config.toml)}"
echo
echo "== $HOST in $manifest =="
awk -v h="$HOST" '$1 == h {p=1} p {print} p && /]/ {exit}' "$manifest"

cat <<EOF

Next, from $VAULT (one YubiKey touch per secret, carbon must be up):
  nix develop -c agevault push $HOST   # expect every line: updated
  nix develop -c agevault push $HOST   # expect every line: unchanged
EOF
