# mTLS Client Certificate Authentication

This guide covers mutual TLS (mTLS) for protecting services with client certificate authentication. Uses a self-hosted step-ca Certificate Authority with Caddy reverse proxy integration.

## Architecture

- **step-ca**: Self-hosted Certificate Authority running on carbon
- **Caddy**: Reverse proxy with `client_auth` directive for mTLS-enabled vhosts
- **Credentials**: CA keys encrypted with systemd-creds, loaded at runtime

The CA issues client certificates that browsers/clients present when connecting to protected services. Server TLS remains Let's Encrypt (unchanged).

## Modules

| Module | Purpose |
|--------|---------|
| `nix/modules/nixos/mtls.nix` | CA server, bootstrap init, cert issuance service |
| `nix/modules/nixos/client-mtls.nix` | Client-side renewal timer (for NixOS machines) |

## Initial Setup (Carbon)

1. Import the module in `nix/hosts/carbon/configuration.nix`:

```nix
{flake, ...}: {
  imports = [
    flake.nixosModules.mtls
  ];
}
```

2. Add DNS entry in `homelab.toml`:

```toml
[dns."gio.ninja".cname]
"carbon.lan." = [
  # ... existing entries
  "ca",
]
```

3. Deploy carbon. On first boot, `step-ca-init` will:
   - Generate root and intermediate CA keypairs
   - Encrypt credentials to `/usr/lib/credstore.encrypted/`
   - Create `/var/lib/step-ca/config/ca.json`

## Enabling mTLS on a Virtual Host

In the service configuration:

```nix
services.gio.reverse-proxy.virtualHosts."myservice" = {
  host = "localhost";
  port = 8080;
  mtls = true;  # Require client certificate
};
```

Clients without a valid certificate will receive `ERR_BAD_SSL_CLIENT_AUTH_CERT`.

## Issuing Client Certificates

On carbon, use the template service:

```bash
# Issue cert for a client
sudo systemctl start mtls-issue@<clientname>.service

# Example
sudo systemctl start mtls-issue@chromebook.service
sudo systemctl start mtls-issue@pixel7.service
```

Certificates are stored at `/var/lib/step-ca/client-certs/<clientname>/`:

| File | Purpose |
|------|---------|
| `client.crt` | Client certificate |
| `client.key` | Private key |
| `client.p12` | PKCS12 bundle for browser import (no password) |
| `root_ca.crt` | CA root certificate |
| `intermediate_ca.crt` | Intermediate CA certificate |
| `ca-chain.crt` | Full CA chain |

Certificates are valid for 1 year by default.

## Installing Certificates

### Browser (Chrome, Firefox, Edge)

1. Copy the `.p12` file to the device:

```bash
scp server@carbon.gio.ninja:/var/lib/step-ca/client-certs/<name>/client.p12 ~/
```

2. Import into browser:
   - **Chrome**: Settings → Privacy and Security → Security → Manage certificates → Your certificates → Import
   - **Firefox**: Settings → Privacy & Security → Certificates → View Certificates → Your Certificates → Import
   - **Edge**: Settings → Privacy, search, and services → Security → Manage certificates → Personal → Import

The `.p12` has no password — leave the password field empty when importing.

### NixOS Machine

1. Copy certificates from carbon:

```bash
sudo mkdir -p /var/lib/mtls-client
sudo scp server@carbon.gio.ninja:/var/lib/step-ca/client-certs/<hostname>/client.crt /var/lib/mtls-client/
sudo scp server@carbon.gio.ninja:/var/lib/step-ca/client-certs/<hostname>/client.key /var/lib/mtls-client/
sudo scp server@carbon.gio.ninja:/var/lib/step-ca/client-certs/<hostname>/root_ca.crt /var/lib/mtls-client/
sudo chmod 600 /var/lib/mtls-client/client.key
```

2. Import the `client-mtls` module for automatic renewal:

```nix
{flake, ...}: {
  imports = [
    flake.nixosModules.client-mtls
  ];
}
```

The module runs a daily timer to renew the certificate before expiry.

### Mobile Devices

Copy `client.p12` to the device and import:

- **iOS**: AirDrop or email the file, tap to install, enter device passcode
- **Android**: Settings → Security → Encryption & credentials → Install certificates → VPN & app user certificate

## Certificate Renewal

### Browser Clients

Certificates last 1 year. Before expiry:

```bash
# Re-issue on carbon
sudo systemctl start mtls-issue@<clientname>.service
```

Then re-import the new `.p12` (delete old cert first).

### NixOS Clients

The `client-mtls` module handles renewal automatically via daily timer.

## Reinitializing the CA

If you need to regenerate the CA (lost credentials, config changes):

```bash
# On carbon
sudo rm -rf /var/lib/step-ca
sudo rm -f /usr/lib/credstore.encrypted/intermediate_ca_key
sudo rm -f /usr/lib/credstore.encrypted/ca-password
```

Then redeploy. All existing client certificates will be invalidated.

## Troubleshooting

### "ERR_BAD_SSL_CLIENT_AUTH_CERT"

- Certificate not imported, or wrong certificate selected
- Certificate expired (check expiry date in browser cert manager)
- Certificate issued by different CA (after CA reinit)

### Chrome doesn't prompt for certificate

- Clear browser cache and retry
- Check `chrome://settings/certificates` — cert should appear under "Your certificates"
- Verify the site has `mtls = true` and Caddy was reloaded

### step-ca won't start

Check credentials are present:

```bash
ls -la /usr/lib/credstore.encrypted/
# Should contain: intermediate_ca_key, ca-password
```

Check CA config exists:

```bash
ls -la /var/lib/step-ca/config/ca.json
```

### Certificate issuance fails

Check step-ca is running:

```bash
systemctl status step-ca
```

Check logs:

```bash
journalctl -u mtls-issue@<name>.service
```

## File Locations

| Path | Contents |
|------|----------|
| `/var/lib/step-ca/config/ca.json` | CA configuration |
| `/var/lib/step-ca/certs/` | CA certificates (root, intermediate, bundle) |
| `/var/lib/step-ca/db/` | Certificate database |
| `/var/lib/step-ca/client-certs/` | Issued client certificates |
| `/usr/lib/credstore.encrypted/` | Encrypted CA credentials |
| `/var/lib/mtls-client/` | Client certificate location (NixOS clients) |
