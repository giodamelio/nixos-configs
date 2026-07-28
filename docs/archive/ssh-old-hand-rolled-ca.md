# SSH Certificates & Access Grants

SSH trust across the fleet via certificates from a homelab SSH CA, plus
nixus-style declarative access grants. Host certs kill TOFU/known_hosts
management; user certs + principals authorize logins; plain authorized_keys
(compiled from the same grants) stay forever as break-glass.

## Architecture

- **ssh-ca** (`modules/packages/ssh-ca/`): one nushell CLI (`init` / `sign`)
  around a step-managed CA *directory* on cadmium — **no daemon**. Signing is
  offline against `$STEPPATH=/var/lib/ssh-step-ca`; the CA password is the
  only secret (TPM-bound in cadmium's credstore). The same `$STEPPATH` can
  later run a real `step-ca` daemon (SSHPOP auto-renewal, OIDC user login via
  Pocket ID) without re-keying.
- **Facts live in den** (`modules/aspects/ssh/`):
  - `host.ssh.{hostKey,extraPrincipals}` — required per host (`null` =
    deliberately not enrolled)
  - `user.ssh.{publicKey,accessTo}` — per user-on-host grants
  - `fleet.ssh.{externalClients,revocations}` — fleet registries on the den
    fleet entity (typed via `den.schema.fleet`, values in `clients.nix`)
- **Certs and CA pubkeys are public data**, committed under
  `modules/aspects/ssh/data/` and deployed like any config. Zero secrets
  ever cross a machine boundary.
- 1-year validity everywhere; a weekly timer on cadmium re-signs anything
  with <90 days left and tells you (journal) to copy + commit.

| Module | Purpose |
|--------|---------|
| `modules/fleet.nix` | Generic den fleet entity (fleet-wide typed facts) |
| `modules/aspects/ssh/schema.nix` | host/user/fleet ssh option declarations |
| `modules/aspects/ssh/clients.nix` | external clients + revocations registry |
| `modules/aspects/ssh/ca.nix` | CA aspect on cadmium: init oneshot, sign oneshot + weekly timer |
| `modules/aspects/ssh/host-cert.nix` | fleet-wide: `@cert-authority` trust, HostCertificate, KRLs |
| `modules/aspects/ssh/access.nix` | grants → authorized_keys, principals, matchBlocks, report |

## Two parallel auth paths for users

1. **Key-based (permanent break-glass)**: every grant
   `user.ssh.accessTo.<toHost>.<toUser> = true` puts the granting pubkey in
   the target account's authorized_keys. No certs involved. Never removed.
2. **Cert-based**: certs are *never* registered in authorized_keys. Targets
   trust the user CA (`TrustedUserCAKeys`), and each granted account gets an
   `AuthorizedPrincipalsFile` accepting exactly `<account>@<host>` — which is
   precisely the principal set the signer mints into certs from the same
   grants. No grant ⇒ no principals file ⇒ cert auth simply doesn't apply.

## Runbooks

### `ssh-ca sync` — the one command on the CA host

`ssh-ca sync` (installed on cadmium by the ssh-ca aspect) is the whole
CA-host workflow, idempotent: triggers `ssh-ca-init` + `ssh-ca-sign` via
systemd (no-ops when already done / nothing to renew), then copies every
public artifact — CA pubkeys, host certs, user/client certs — into
`~/nixos-configs/modules/aspects/ssh/data/` (only files whose content
changed; `--repo` overrides the checkout path). It prints what changed;
you commit and deploy.

A **pre-push prek hook** (`check-ssh-data`, backed by the
`ssh-data-complete` flake check) fails the push if the den config requires
certs/CA pubkeys that aren't committed under `data/` — so you can't forget
to run it.

### Bootstrap the CA (once)

1. Deploy cadmium. `ssh-ca-init` fires on boot (gated on
   `ConditionPathExists=!/var/lib/ssh-step-ca/config/ca.json`).
2. `ssh-ca sync`, then `git add` the new files under
   `modules/aspects/ssh/data/`, commit, deploy the fleet. Every host now
   trusts the CA.

### Enroll a host

1. `ssh-keyscan -t ed25519 <host>` → paste into
   `den.hosts.<sys>.<host>.ssh.hostKey` (cross-check against
   `/etc/ssh/ssh_host_ed25519_key.pub` on the console if paranoid).
   (A host that isn't deployed yet sets `ssh.enable = false` instead — it
   is invisible to the whole SSH system until flipped.)
2. Rebuild cadmium (bakes the host into the signer targets), then
   `ssh-ca sync`.
3. `git add` the new cert, commit, deploy the host.
4. Verify: `ssh -v <host> 2>&1 | grep 'Host certificate'`, and a fresh
   known_hosts (`ssh -o UserKnownHostsFile=/tmp/kh <host>`) gets no TOFU
   prompt.

### Grant access (nixus-style)

```nix
den.hosts.x86_64-linux.cadmium.users.giodamelio.ssh = {
  publicKey = "ssh-ed25519 AAAA…";   # cat ~/.ssh/id_ed25519.pub
  accessTo.gallium.root = true;
  accessTo.cesium.giodamelio = true;
};
```

Deploy the *target* hosts (authorized_keys + principals) and the granting
host (matchBlocks). Targets are validated at eval time — a typo'd host/user
is a build error. To also get a user *certificate*, run the signer and commit
the cert from `/var/lib/ssh-ca/certs/clients/<user>@<host>-cert.pub` into
`data/certs/clients/`.

### Enroll an external client (Termius on Android)

1. Generate a keypair **in Termius** (the private key never leaves the
   phone); export the public key.
2. Add it to `modules/aspects/ssh/clients.nix`:
   ```nix
   fleet.ssh.externalClients.termius-phone = {
     publicKey = "ssh-ed25519 AAAA…";
     accessTo.cadmium.giodamelio = true;
   };
   ```
3. Rebuild cadmium, `ssh-ca sync`, then get
   `/var/lib/ssh-ca/certs/clients/termius-phone-cert.pub` to the phone (it's
   public — clipboard is fine).
4. In Termius: the key → **Add certificate** → paste.
5. Deploy the target hosts. The same grants also compile to authorized_keys,
   so the phone works key-based even without the cert. (Termius can't do
   `@cert-authority`, so the phone TOFUs host keys — fine.)

Re-import a fresh cert roughly yearly (the signer renews it; the phone
import is the manual part).

### Revoke a certificate

OpenSSH has no OCSP/CRL — revocation is **KRLs** (Key Revocation Lists),
built at *build time* from the registry (only the CA *public* key is needed):

1. Add a spec line to `fleet.ssh.revocations` in `clients.nix`:
   - `"id: termius-phone"` — kills every cert ever issued to that identity
     (key IDs are the target names used at signing)
   - `"serial: 123456"` — one specific cert (`ssh-keygen -Lf <cert>`)
   - `"key: ssh-ed25519 AAAA…"` — a raw key, certs or not
2. Remove the identity's grants / `ssh.hostKey`.
3. Deploy the fleet — sshd enforces `revocations.users` via `RevokedKeys`,
   ssh clients enforce `revocations.hosts` via `RevokedHostKeys`. Entries
   stay forever (KRLs are tiny).

### Rotate a host key (reinstall)

The committed cert stops matching: sshd logs a warning and serves the plain
key, clients fall back to TOFU — never a lockout. Re-run the *enroll a host*
runbook with the new key.

### Re-key the CA (cadmium died)

The credstore password is TPM-bound and unrecoverable — accept and re-key
(~30 min, SSH keeps working via authorized_keys/TOFU throughout):

```bash
sudo rm -rf /var/lib/ssh-step-ca /var/lib/ssh-ca
sudo rm -f /usr/lib/credstore.encrypted/ssh-ca-password
```

Reboot (init re-fires), `ssh-ca sync`, recommit everything under `data/`,
deploy the fleet.

## The access report

The full declared matrix is rendered on every host at
**`/etc/nix-metadata/ssh-access`** — one `from -> toUser@toHost` line per
grant, straight from the deployed config.

## Expiry posture

1-year certs, weekly auto re-sign under 90 days (`ssh-ca-sign.timer`),
journal warning when fresh certs are waiting to be committed. An expired
cert degrades softly: sshd serves the plain key → clients TOFU;
authorized_keys auth is untouched. There is deliberately no repo-hook expiry
check; if a push nudge ever proves wanted, a gatus check on carbon is the
natural home.

## Future works

- **Pipes-based reporting**: today grants are declared entity facts read at
  file scope. If service aspects ever *emit* grants (e.g. zfs-backup
  declaring syncoid access), collect them den-natively with quirk pipes —
  `pipe.expose` (user→host) + `pipe.collect` (across hosts) — and the report
  upgrades from "declared" to "emitted" without changing consumers. The
  matrix could also be published to monitoring/gatus.
- **Growing the fleet entity**: `modules/fleet.nix` is generic infra. Future
  fleet-level registries (`fleet.services.*`, backup topology,
  `fleet.secrets` — see docs/fleet-secrets.md) follow the same pattern:
  declare typed options in `den.schema.fleet.imports`, set values via
  `fleet.<feature>.*` from the feature's own files, consume via the
  `{fleet, ...}` context arg.
- **den-diagram access graphs**: `denful/den-diagram` (separate pure-lib
  flake input; den's `den.lib.capture` half is already pinned) models fleets
  as `relations = [{from, to, label}]` — exactly the grant matrix's shape —
  with Mermaid/C4/DOT/sankey renderers and export helpers (`mkGallery`,
  `mkWriteScript`) that could auto-generate a who-can-access-whom
  markdown+SVG gallery in `docs/` from the same data. The fleet entity is
  also what den's own fleet-view machinery hangs off, so these converge.
- **Online CA**: add a `step-ca` daemon over the same `$STEPPATH` +
  provisioners for SSHPOP host-cert auto-renewal and `step ssh login`
  (OIDC/Pocket ID) short-lived user certs — strictly additive, no re-keying.

## File locations

| Path | Contents |
|------|----------|
| `/var/lib/ssh-step-ca/` | step CA directory (keys password-encrypted) |
| `/usr/lib/credstore.encrypted/ssh-ca-password` | the one secret (cadmium, TPM-bound) |
| `/var/lib/ssh-ca/{host,user}-ca.pub` | CA pubkeys (paste into repo `data/`) |
| `/var/lib/ssh-ca/certs/` | freshly signed host certs (copy into repo) |
| `/var/lib/ssh-ca/certs/clients/` | user/external-client certs (copy into repo) |
| `modules/aspects/ssh/data/` | committed CA pubkeys + certs (public) |
| `/etc/ssh/ssh_host_ed25519_key-cert.pub` | deployed host certificate |
| `/etc/ssh/user-ca.pub`, `/etc/ssh/authorized-principals/` | user-cert trust |
| `/etc/nix-metadata/ssh-access` | rendered access-grant matrix |
