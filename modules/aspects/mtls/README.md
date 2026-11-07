# gio.mtls

Service certificates from strontium's step-ca `app` provisioner. Each certificate is declared in NixOS config, enrolled once by hand, and renewed automatically. The host can never choose or change a certificate's identity: the CN, SANs and role are signed into the enroll token on strontium.

The aspect is on every host through `den.default` and does nothing until a host declares a certificate.

## Declare a certificate

```nix
gio.mtls.certs.vmagent = {
  role = "telemetry-writer";        # becomes the OU
  services = ["vmagent"];           # each gets LoadCredential=
  onRenew = "restart";
};

gio.mtls.certs.telemetry-node = {
  role = "telemetry-cluster";
  serverHostnames = ["carbon.gio.ninja"];
  serverAddresses = ["10.30.0.10"];
  onRenew = "reload-caddy";
};
```

| Option | Meaning |
|---|---|
| `app` | Application name, defaults to the attribute name. |
| `role` | Signed into the certificate as the OU. Callers are authorized by it. |
| `serverHostnames` | DNS SANs. Only names that resolve to this host; pure clients have none. |
| `serverAddresses` | IP SANs, for peers that dial and verify by IP. Only addresses of this host, in canonical form (`fd00::1`), since the drift check compares them verbatim. |
| `services` | systemd services that consume the certificate (`.service` optional). |
| `onRenew` | `restart` or `reload` the `services`, or `reload-caddy` (`systemctl reload caddy`). |

Read-only values to point consumers at:

- `cn`, `uri`: the derived identity (next section).
- `certFile`, `keyFile`: `/var/lib/mtls/<name>/cert.pem` and `key.pem`, owned by root. With `onRenew = "reload-caddy"` they are group-readable by `caddy`, so Caddy reads them directly and picks up a renewal on reload.
- `gio.mtls.caRoot`: `/etc/step/ca-root.crt`, the trust pool for verifying peers.

Each unit in `services` gets `LoadCredential=` for `mtls-<name>-cert`, `mtls-<name>-key` and `mtls-ca`, readable at `$CREDENTIALS_DIRECTORY/<id>`; this works with `DynamicUser=`. systemd copies credentials when the unit starts, so a unit that only reloads keeps the old certificate in its credentials directory. Use `reload` only for services that read `certFile` themselves.

A consuming unit fails to start until its certificate is enrolled. Enrollment then starts it.

## Follow the naming conventions

For application `<app>` on host `<host>`:

- **CN:** `<app>.<host>`
- **URI SAN:** `spiffe://gio.ninja/<host>/<app>`
- **O:** `app`, the provisioner. Only the `app` template sets an OU, so an OU match also proves the certificate came from `app`.
- **OU:** the role, e.g. `telemetry-writer`.

Authorize callers by CN or OU, never merely by "has a valid certificate".

## Enroll a host

1. Deploy the host with the declaration, and deploy strontium so `ca-enroll-host` knows about it.
2. On strontium, run `sudo ca-enroll-host <host> mtls`. To enroll only some certificates, add `--role <role>`; it fails when no declaration on that host uses the role.
3. Check the CN, role and SANs it prints, then paste the commands into a shell on the host within 30 minutes.

Each pasted command drops a token into `/var/lib/mtls/tokens/`. `mtls-enroll.path` picks it up, deletes it, requests the certificate, checks it against the declaration and runs the `onRenew` action.

## Understand renewal and the drift check

`mtls-renew.timer` runs every 12 hours. For each certificate it:

1. Compares the CN, URI SAN, O, OU, DNS SANs and IP SANs on disk with the declaration.
2. Runs `step ca renew --expires-in 120h`, which renews once a certificate is about 2 days old.
3. Runs the `onRenew` action when a new certificate was issued.

Renewal copies the old certificate, so a renewal can never change the identity. When a declaration changes (a new role, another hostname), the drift check fails `mtls-renew.service`, names the certificate and stops renewing it. Reissue it with `ca-enroll-host`.

Certificates last 7 days and cannot renew after they expire. A host that is off for longer needs `ca-enroll-host` again.

## Revoke and reissue a certificate

When a certificate is compromised, or its identity must change:

1. On strontium, run `sudo ca-revoke <cn>`, e.g. `sudo ca-revoke vmagent.carbon`.
2. Change the declaration if needed, deploy the host and strontium.
3. Run `sudo ca-enroll-host <host> mtls --role <role>` and paste the output on the host.

`ca-revoke` revokes the newest serial for the CN in step-ca's JSON journal. Always revoke the newest: every renewal issues a new serial, so revoking an older one leaves the certificate in use alive.

Revocation blocks renewal, so the certificate dies within its lifetime at the latest. step-ca also rebuilds its CRL at once, served at `http://crl.gio.ninja/` and named in every certificate's CRL distribution point, so verifiers that check CRLs reject it within minutes.
