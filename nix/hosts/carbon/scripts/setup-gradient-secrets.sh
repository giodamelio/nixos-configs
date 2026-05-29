#!/usr/bin/env bash
set -euo pipefail

CREDSTORE="/usr/lib/credstore.encrypted"
mkdir -p "$CREDSTORE"

echo "=== Gradient Secret Setup ==="
echo ""

# Worker UUID
WORKER_UUID=$(uuidgen)
echo "Generated Worker UUID: $WORKER_UUID"
echo "  → Put this in gradient.nix as workerUuid"
echo ""

# JWT secret
openssl rand -base64 48 | systemd-creds encrypt \
  --name=gradient-jwt-secret - "$CREDSTORE/gradient-jwt-secret"
echo "[OK] gradient-jwt-secret"

# DB encryption key
openssl rand -base64 48 | systemd-creds encrypt \
  --name=gradient-crypt-secret - "$CREDSTORE/gradient-crypt-secret"
echo "[OK] gradient-crypt-secret"

# Metrics bearer token
openssl rand -base64 32 | systemd-creds encrypt \
  --name=gradient-metrics-token - "$CREDSTORE/gradient-metrics-token"
echo "[OK] gradient-metrics-token"

# Worker token (shared between server and worker)
WORKER_TOKEN=$(openssl rand -base64 48)
printf '%s' "$WORKER_TOKEN" | systemd-creds encrypt \
  --name=gradient-worker-token - "$CREDSTORE/gradient-worker-token"
echo "[OK] gradient-worker-token"

# Worker peers file (worker uses this to authenticate with server)
printf '%s:%s' "$WORKER_UUID" "$WORKER_TOKEN" | systemd-creds encrypt \
  --name=gradient-worker-peers - "$CREDSTORE/gradient-worker-peers"
echo "[OK] gradient-worker-peers"

# Organization private key
openssl genpkey -algorithm ed25519 2>/dev/null | systemd-creds encrypt \
  --name=gradient-org-private-key - "$CREDSTORE/gradient-org-private-key"
echo "[OK] gradient-org-private-key"

# Forgejo webhook HMAC secret
WEBHOOK_SECRET=$(openssl rand -base64 32)
printf '%s' "$WEBHOOK_SECRET" | systemd-creds encrypt \
  --name=gradient-forgejo-webhook-secret - "$CREDSTORE/gradient-forgejo-webhook-secret"
echo "[OK] gradient-forgejo-webhook-secret"

# Nix binary cache signing key
nix key generate-secret --key-name gradient-cache | systemd-creds encrypt \
  --name=gradient-cache-signing-key - "$CREDSTORE/gradient-cache-signing-key"
echo "[OK] gradient-cache-signing-key"

echo ""
echo "=== SAVE THESE VALUES ==="
echo ""
echo "Worker UUID (for gradient.nix):  $WORKER_UUID"
echo "Webhook Secret (for Forgejo):    $WEBHOOK_SECRET"
echo ""
echo "=== REMAINING MANUAL STEPS ==="
echo ""
echo "1. Create Pocket ID OIDC client at https://login.gio.ninja"
echo "   - Client ID: gradient"
echo "   - Redirect URI: https://gradient.gio.ninja/api/auth/oidc/callback"
echo "   - Then run:"
echo "     echo -n '<CLIENT_SECRET>' | systemd-creds encrypt \\"
echo "       --name=gradient-oidc-client-secret - $CREDSTORE/gradient-oidc-client-secret"
echo ""
echo "2. Create Forgejo access token at https://forgejo.gio.ninja"
echo "   - Settings → Applications → Generate token (repo write perms)"
echo "   - Then run:"
echo "     echo -n '<TOKEN>' | systemd-creds encrypt \\"
echo "       --name=gradient-forgejo-access-token - $CREDSTORE/gradient-forgejo-access-token"
echo ""
echo "3. Create Garage key + bucket (on gallium):"
echo "   garage -c /etc/garage.toml key create gradient"
echo "   garage -c /etc/garage.toml bucket create gradient-cache"
echo "   garage -c /etc/garage.toml bucket allow gradient-cache --read --write --key gradient"
echo "   - Then on carbon:"
echo "     echo -n '<GARAGE_SECRET_KEY>' | systemd-creds encrypt \\"
echo "       --name=gradient-s3-secret-key - $CREDSTORE/gradient-s3-secret-key"
echo "   - Update accessKeyId in gradient.nix with the Garage Key ID"
echo ""
echo "4. After deploy, configure Forgejo webhook:"
echo "   - URL: https://gradient.gio.ninja/api/webhook/forgejo"
echo "   - Content type: application/json"
echo "   - Secret: $WEBHOOK_SECRET"
echo "   - Events: Push, Pull Request"
