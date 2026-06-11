# credsync — Copying systemd-creds Between Hosts

`credsync` idempotently copies systemd credentials from the host that generates
them to the hosts that consume them, over SSH. Typical flow: a host generates an
API token into its encrypted credstore, and a systemd unit pushes it to the
machine that calls that API — no manual steps.

## Why it works the way it does

Encrypted credential blobs are bound to the local host key/TPM, so a blob from
one machine is useless on (and incomparable with) another. credsync therefore
ships the *plaintext*, but only ever through stdin/pipes inside the SSH channel
— never on argv, never unencrypted on disk. The **receiver** does the change
detection: it decrypts its existing credential, compares plaintexts, and only
re-encrypts + signals consumers when the value actually changed. That makes
pushes safe to run repeatedly (boot, timers): an unchanged secret means no
rewrite, no target activation, no service restarts.

## Usage

```sh
# On the generating host: push a credential to another machine.
credsync push <name> <ssh-destination> [restart-units...]

# On the receiving host (normally invoked via ssh by push):
#   reads the secret from stdin, stores it in the credstore.
credsync write <name> [restart-units...]
```

- `push` prints the receiver's verdict: `unchanged` or `updated`.
- A non-`root@` destination automatically wraps the remote command in
  `sudo -n` (the credstore and `systemctl` need root).
- On change, the receiver best-effort starts `credsync-<name>.target` (so
  consumers can gate on the credential's existence) and `systemctl
  try-restart`s any listed restart units. Both are skipped when unchanged.
- Exit code 0 means synced-or-unchanged, so `push` works directly as a
  `Type=oneshot` `ExecStart`.

### Example

```sh
# carbon generates the token:
openssl rand -hex 32 | systemd-creds encrypt --name=some-api-token - \
  /usr/lib/credstore.encrypted/some-api-token

# and pushes it to gallium, restarting the consumer when it changed:
credsync push some-api-token root@gallium.gio.ninja some-consumer.service
```

## Configuration (environment variables)

| Variable | Default | Purpose |
|----------|---------|---------|
| `CREDSTORE_DIR` | `/usr/lib/credstore.encrypted` | Credstore location (override for root-less testing) |
| `CREDSYNC_CREDS_ARGS` | (empty) | Extra `systemd-creds` args, e.g. `--with-key=auto` on TPM-less machines |

## Caveats

- Capturing decrypt output strips trailing newlines — fine for tokens;
  byte-exact binary credentials are out of scope.
- SSH auth is assumed to already work (`BatchMode=yes` — it will fail rather
  than prompt).

## Code & Tests

| Path | Purpose |
|------|---------|
| `modules/packages/credsync/credsync.nu` | The script (one nushell binary, `push`/`write` subcommands) |
| `modules/packages/credsync/credsync.nix` | flake-parts package + check wiring |
| `modules/packages/credsync/_test.nix` | Two-VM NixOS test (`passthru.tests.vm`) |

Run the end-to-end test: `nix build .#checks.x86_64-linux.credsync-vm`

## TODO / Future Work

- [ ] **den aspect** wrapping the script: per-(credential × host) push oneshot
      units/timers generated from den schema facts (grouped under one
      feature-named attrset, e.g. `host.credsync.*`), ordered after the unit
      that generates the secret, with retry while the target is down.
- [ ] **`credsync-<name>.target` + path unit** on receiving hosts: watch the
      credstore file and activate the target when it appears, so consuming
      services can `after`/`requires` it and wait for first delivery. (The
      script already best-effort starts the target on change.)
- [ ] **Dedicated SSH identity**: keypair generated on first boot (like
      `wg-nfs-keygen`), private key in the credstore, pubkey in
      `homelab.toml`; receiving hosts get a forced-command `authorized_keys`
      entry locked to `credsync write` (parse `SSH_ORIGINAL_COMMAND`), possibly
      under a dedicated user instead of root.
- [ ] **Byte-exact credentials** (binary blobs / trailing newlines) if ever
      needed — pass data as base64 instead of raw capture.
