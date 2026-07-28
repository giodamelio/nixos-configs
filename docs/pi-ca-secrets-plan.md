# Dedicated Pi: CA + Secret Manager — design plan

High-level plan for a small, isolated Raspberry Pi that serves as (1) a
git-backed **secret manager** and (2) a **Step CA** (X.509 + SSH certs). Draft —
locked decisions and open questions are marked. Supersedes the credsync-based
`fleet.secrets` (see `docs/archive/fleet-secrets-design-superseded.md`) and revisits
the den-migration spec's "never reintroduce mTLS/step-ca" clause (now archived).

## Why

The den migration's secret machinery (credsync push/pull, TPM-bound
`systemd-creds` at rest, cross-host push units, `_`↔`-` renames) caused a
cascade of failures, and the carbon disk incident exposed backup/monitoring gaps
(see `MIGRATION.md`). Goal: a **minimal, isolated root of trust** with
portable age-based secrets, simpler mental model, and no single dependency that
can lock us out or lose data.

## Guiding principle — no circular dependencies

Nothing critical may depend on the thing it protects:
- Secrets delivered to hosts at deploy time (persist on disk) → deploying/booting
  doesn't need the Pi up.
- Break-glass YubiKey in `authorized_keys` → login doesn't need the CA or IdP.
- CA root offline → losing the Pi ≠ losing trust.
- Recovery recipients on hardware/paper → losing the Pi ≠ losing secrets.

## Decisions (all confirmed)

- **age over rage** — `age-plugin-yubikey` for YubiKey recipients.
- **No secrets in the Nix store, ever** (even encrypted). Hard requirement.
- **Secrets at rest = age**, in a **private git repo** (forgejo + Pi mirror),
  never GitHub.
- **Hosts are never age recipients** — decrypt locally (YubiKey), pipe plaintext
  over SSH into `systemd-creds encrypt` on the host.
- **Delivery = `/usr/lib/credstore.encrypted/<name>`**, consumed unchanged via
  `LoadCredentialEncrypted` → `$CREDENTIALS_DIRECTORY`.
- **No agenix** — a small custom nushell CLI drives the offline age repo + push.
- **CA replaces** the `modules/aspects/ssh` CA. **SSH CA first**, mTLS later.
- **CA = two-tier PKI**, offline root → **5–10 y intermediate**; the Pi **runs
  only the intermediate**.
- **Offline root** on an encrypted USB, age-encrypted to **YubiKey A + B**, plus
  a **paperage** backup.
- **All keygen on the Pi**, online-minimal ceremony: generate into **tmpfs**,
  write only ciphertext to the USB, `paperage` it, sign the intermediate in RAM,
  wipe — the root never lands on the SD.
- **Unified recovery set** (YubiKey A + B + paper age key) across the root *and*
  all secrets.
- **Three-tier SSH access** kept.
- **Node stays dedicated/isolated** — no other services co-located.
- **Board = Pi 3B+**; **storage: SD-only** (no USB, no ZFS) — **ext4 + NixOS
  generations + restic → garage**. High-endurance SD, minimize writes (journald
  to RAM/size-capped, tmpfs for churn).
- **Node identity:** hostname **strontium**, static **10.30.0.13**, DNS
  **ca.gio.ninja** (A record → the IP; **not** behind Caddy — step-ca binds its
  own port). **One step-ca instance** = SSH CA now, X.509 + ACME later.
- **Phase-1 principals:** user certs for `giodamelio` on **cadmium**, **cesium**,
  and the **phone (Terminus)**.

## Secret manager (successor to fleet.secrets)

Not a server — a **local nushell CLI** (packaged from this repo, run against a
separate offline secrets repo) plus a names-only manifest the flake consumes.

> **Built (2026-07-03) — deviations from the draft below.** The CLI is
> **`agevault`** (`modules/packages/agevault/`, VM test passes). The manifest is
> **TOML, not Nix** — `generate-toml` writes `secrets.toml` (committed at the
> repo root by default; the consumer path is the configurable
> `fleet.credentials.manifestFile`, and `config.toml`'s key is `manifest_path`).
> Verification lives in the **`fleet.credentials`** aspect
> (`modules/aspects/credentials/`, wired into `den.default`): read-only
> `fleet.credentials.{available,manifest}` facts + an eval-time assertion that
> every `fleet.credentials.needs` entry is deliverable (missing file OR missing
> secret = hard error). It reads the explicit `needs`, **not `gio.credentials`**
> (which is dead in the den tree — needs are declared via fleet.secrets
> use-sites). Eventual goal: fold delivery + consumption into `fleet.credentials`.

**Offline secrets repo** — mirrored to forgejo + the Pi (as an encrypted bare
remote; the Pi isn't a recipient so it only holds ciphertext). The flake knows
nothing about it:

```
recipients.txt              # age recipients: YubiKey A, YubiKey B, paper recovery
config.toml                 # secrets_nix_path -> abs path into nixos-configs (gitignored)
config.toml.example
common/<name>.age           # shared secrets
hosts/<host>/<name>.age     # per-host; shared ones are symlinks into common/
```

- **Filename (sans `.age`) == the systemd credential name, verbatim.**
  ~~incl. `secrets.json`~~ — **amended 2026-08-23**, see "Naming" below.
  **One recipient set for everything** — hosts aren't recipients, so there are no
  per-host recipient lists.

**CLI** — `writeNushellApplication`, subcommands, VM tests as `passthru.tests`,
exported as a package from nixos-configs and run inside the secrets repo:

- `cat <host> <name>` — decrypt to stdout (YubiKey).
- `edit <host> <name>` — decrypt → `$EDITOR` → re-encrypt; creates if missing (= add).
- `rm <host> <name>` — delete the `.age`.
- `push <host> [name]` / `push` (all) — `age -d` locally (YubiKey) piped to
  `ssh host 'sudo systemd-creds encrypt --name=<name> - /usr/lib/credstore.encrypted/<name>'`
  (dir `0700`, blob `0400`, root). Plaintext lives only in the pipe.
- `rekey` — re-encrypt everything to the current `recipients.txt` (after rotating
  a YubiKey / recovery key).
- `generate-nix` — write the manifest to `secrets_nix_path`; runs **automatically
  after `edit`/`rm`**, also manual.
- **Symlink-aware:** `edit`/`cat`/`rekey`/`push` resolve to the target (shared
  edit updates every consumer); `rekey` dedupes by real path; `generate-nix`
  lists by name so a symlinked secret appears under each consuming host.

**Manifest + eval-time verification** — `generate-nix` emits `secrets.nix`
(names only, safe to commit):

```nix
{ carbon = [ "forgejo-oidc-client-id" "secrets.json" ]; gallium = [ "netdata-api-key" ]; }
```

`gio.credentials` imports it and **asserts at eval time** that every credential a
service declares exists in the manifest for that host — turning the zwave-js /
mealie / prometheus missing-or-misnamed-secret failures into **build errors**.
(Optional `verify` complements it with a live check that the blob is on the box.)

### Decided 2026-08-23 — agevault is the only delivery path

Settled while planning carbon's rebuild. Supersedes the "built additively
alongside credsync, cut over one secret at a time" approach: the cutover happens
in one pass, and `fleet.secrets` survives as the **emission** layer rather than
being reimplemented. Execution plan: `MIGRATION.md` -> "Retire the delivery half
of fleet.secrets".

**Why the swap is a no-op at the blob level.** Both tools write the same file, to
the same directory, with the same command:

```
credsync.nu:88    $incoming | ^systemd-creds encrypt ...(creds-args) "--name=" - $tmp
agevault.nu:242   systemd-creds encrypt --name="$name" - "$dir/.$name.tmp" < "$tmp"

_expand.nix:30    credstoreDir = "/usr/lib/credstore.encrypted"
agevault.nu:67    $env.AGEVAULT_CREDSTORE_DIR? | default "/usr/lib/credstore.encrypted"
```

`fleet.secrets` never cared who wrote the blob — provision units are gated on
`ConditionPathExists=!<blobPath>`, and the `.path`/`.target` gating and the
drop-ins only ever read that path. So agevault replaces delivery with **zero
service-file rewiring**.

**What `fleet.secrets` keeps:** use-sites (`unit`, `type`, `credential.name` /
`.source` / `.encrypted`, `env-wrapper.variable`, `restartOnChange`, `upholds`),
the credential drop-ins, the env-wrapper `ExecStart` rewrite, `.path`/`.target`
gating, the login warning, and eval-time validation.

**What it loses:** `generator` (values are minted by hand into the vault),
`origin`, `copyTo`, the push units/timers, the push keygen, the forced-command
SSH wrapper, `[credsync_push_keys]`, and the `credsync` package itself.

Accepted cost: adding a host to the NFS mesh no longer auto-mints its WireGuard
keypair. It becomes a `wg genkey`, two `agevault write`s, and a manifest regen.

### Naming

**snake_case only** — `[a-z0-9_]+`, no `-` and no `.`. This amends the original
"filename == credential name verbatim (incl. `secrets.json`)" rule: generic or
dotted names do not go in the shared credential namespace. Where a consumer
demands a specific id, **fix the consumer**, not the vault name.

`nameRe`/`credentialIdRe` in `modules/aspects/secrets/_lib.nix` become
`[a-z0-9_]+` and `[a-z0-9._]+` respectively (ids may keep a dot; names may not).

### The named-blob constraint (why the naming rule is load-bearing)

credsync wrote blobs **nameless** (`--name=`); agevault writes them **named**.
That one byte changes what is legal:

- A **nameless** blob loads under any credential id.
- A **named** blob loads **only** when the id equals the embedded name.

systemd enforces this in `src/shared/creds-util.c`:

```c
if (validate_name && !streq(embedded_name, validate_name))
    return log_error_errno(SYNTHETIC_ERRNO(EDESTADDRREQ),
        "Embedded credential name '%s' does not match filename '%s', refusing.");
```

So every `LoadCredentialEncrypted=<id>:<blob>` **rename** breaks under agevault
unless id == blob name. Hence snake_case everywhere and consumer-side fixes.

**`ImportCredential=` does not rescue this.** It searches the same credstore dirs
and supports `ImportCredential=source:renamed`, so it looks like the answer. It
is not — `src/core/exec-credential.c` renames *before* decrypting:

```c
if (ic->rename) { ... free_and_replace(fn, renamed); }   // fn is now the RENAMED name
r = maybe_decrypt_and_write_credential(args, fn, data, size, /* graceful= */ true);
```

`fn` becomes `validate_name`, so it validates against the renamed id and hits the
same mismatch. Worse, `graceful = true` means it logs a warning and **silently
skips the credential** instead of failing the unit. Verified against systemd 260.

`SYSTEMD_CREDENTIAL_VALIDATE_NAME=0` disables the check, but it is a
service-manager-wide env var — too blunt to use. Injecting a file into `%d` via
`BindPaths=` is also out: the credentials directory is a per-unit tmpfs systemd
sets up after mount-namespace configuration.

### The three consumers that force a rename

| Secret | Required id | Why | Fix |
| --- | --- | --- | --- |
| `wg_nfs_priv_<h>` | `wg-priv` | our own override | drop it (`aspects/nfs/secrets.nix:23`); use the full name |
| `consul_encrypt` | `consul_encrypt.json` | consul parses `-config-file` by extension | try `-config-format=json`; else materialise a `.json` path in `ExecStartPre` |
| `zwavejs_secrets` | `secrets.json` | upstream hardcodes `%d/secrets.json` | override the `ExecStartPre` |

The zwave case is genuinely upstream — `nixos/modules/services/home-automation/zwave-js.nix`
bakes the path into the command line, and `secretsConfigFile` only controls the
*source*, not the id:

```nix
ExecStartPre = ''/bin/sh -c "…jq -s '.[0] * .[1]' ${configFile} %d/secrets.json > ${mergedConfigFile}"'';
LoadCredential = "secrets.json:${cfg.secretsConfigFile}";
```

Gradient is a fourth case but needs no fix: its ~13 `LoadCredentialEncrypted=`
directives are **hand-written** (`modules/hosts/carbon/gradient.nix:276-291`) and
never pass through `nameRe`, so its generated ids — which mix both separators,
e.g. `gradient_worker_4f7f7bfb-6013-405a-9a5f-fc98449725d7_token` — can be used
verbatim as vault filenames with no rename at all.

### Watch for stale twins when loading the vault

carbon's credstore accumulated **two blobs for many secrets**: a live hyphenated
one and a pre-`fleet.secrets` underscore/`.json` twin. They are **not copies** —
`gradient-org-private-key` is 119 B against its twin's 399 B, and
`zwavejs-secrets` is 415 B (the fixed nested `securityKeys` shape) against
`secrets.json` at 262 B (the old flat form that broke).

Rule: take the **value** from the blob the config actually loads, store it under
the new **snake_case name**. Use `agevault write <host> <name> -` for byte-exact
stdin — several twins differ only by a trailing newline.

## Certificate Authority (Step CA)

Mostly-stock `services.step-ca`. **Replaces** the hand-rolled `modules/aspects/ssh`
CA. **SSH CA first**, X.509/mTLS deferred (SSH CA keys are standalone, so no root
ceremony is needed to ship SSH).

- **Distribution split:** the only *secret* material is the CA signing keys, and
  they stay on the Pi. Host-facing material is **public** → flake, not the secret
  system: user-CA pubkey (`TrustedUserCAKeys`), host-CA pubkey (clients'
  `@cert-authority`), per-host **host certs** (minted centrally, distributed as
  flake files — resilient: hosts never contact the CA at runtime, so CA downtime
  doesn't break existing SSH).
- **User certs** → short-lived, `step ssh login` → **Pocket ID OIDC** (2FA).
- **External clients** (phone / Termius secure-enclave): the enclave key is
  non-exportable, so export its **pubkey**, `step ssh certificate --sign` it with
  the JWK provisioner, and **import the cert** into the app (same as today).
- **CA-key backup:** keys are generated on the Pi → their private halves are
  backed up (manually to the USB during the ceremony; later *pulled* into the age
  store). This makes the **Pi disposable** — reflash, re-place keys, same CA.
- mTLS: **deferred** — when wanted, do the offline root → intermediate, push the
  intermediate key via the secret system, enable X.509 provisioners/ACME then.

### Phasing (CA can ship before the secret system)
- **Phase 1:** ✅ minimal NixOS on strontium + ceremony **done** (keys generated +
  backed up — see "Ceremony complete" above). **Remaining in Phase 1 (next up):**
  1. wire `services.step-ca` to read the intermediate + SSH CA keys from
     `/var/lib/gio-ca` (plain on-disk files) + the **JWK provisioner**;
  2. distribute the public trust anchors (`root.crt`, `ssh_user_ca.pub`,
     `ssh_host_ca.pub`) to the fleet (flake);
  3. put both break-glass pubkeys in `authorized_keys` (the safety gate) before
     any sshd `TrustedUserCAKeys` change;
  4. deploy the DNS servers (picks up `ca`/`strontium` records);
  5. mint the first host + user certs by hand via JWK (no OIDC until Pocket
     ID/carbon is back).
- **Phase 2 (later):** flip step-ca key delivery to `LoadCredentialEncrypted` from
  the credstore and **import** the CA keys into the age repo. Pi-local change,
  invisible to the fleet. The two systems don't depend on each other.

## Multi-tier SSH access (break-glass)

1. **Everyday:** `step ssh login` → Pocket ID (2FA) → short-lived cert.
2. **JWK provisioner** (password `age`-encrypted to the YubiKeys). *Not just a
   fallback* — it's the **bootstrap-primary** (no OIDC exists until carbon/Pocket
   ID is back), the external-client (phone enclave) signer, and the host-cert
   minter. (Upgrade to X5C-with-YubiKey once X.509 exists.)
3. **CA down:** YubiKey-resident hardware key (`sk-ssh-ed25519`) in every host's
   `authorized_keys`, independent of CA/IdP/network.
4. Physical fallback: serial/console.
- Nuclear: **paper root → rebuild the CA** on any Linux box (a rebuild event, not
  a "Pocket ID is down this afternoon" tool — that's tier 2).

Rule: the Pi/CA must never be a hard dependency for logging into another host.

## Backups & filesystem

- **SD-only, near-disposable node.** No on-box redundancy — the important bytes
  live off-box (CA keys → offline-root USB + age repo + paperage; secrets →
  desktop/forgejo mirror; config → flake). SD death = reflash + re-place CA keys
  + re-clone the mirror. Not ZFS (heavy/wears the SD/no self-heal on one device),
  no USB drives (no SSDs on hand; flash mirror would be a downgrade).
- **Rollback** from NixOS generations; optional btrfs snapshots as polish.
- [x] **Off-box backup → restic → garage — implemented** on strontium
  (`modules/hosts/strontium/default.nix`): daily timer backs up `/var/lib/gio-ca`
  to the `strontium-backups` garage bucket. Secrets are systemd credentials —
  `restic-password` (`RESTIC_PASSWORD_FILE`) + `restic-s3-credentials` (an AWS
  shared-creds INI via `AWS_SHARED_CREDENTIALS_FILE`); restic ignores `AWS_*_FILE`,
  so that INI trick is how the S3 creds stay in credentials. Inspect with
  `sudo restic-strontium <cmd>` (transient-unit wrapper that loads the same
  creds; the module's auto-wrapper is off). Add `/var/lib/step-ca` once step-ca runs.
- Carbon-incident follow-through (`MIGRATION.md`): schedule ✅ (daily timer);
  **still TODO — alert on staleness + a restore drill** (a backup never restored
  from does not count).
- [ ] **Monitor the restic backups (with a dead-man's switch).** A silently
  broken backup is the carbon incident again. Needed:
  - **Positive heartbeat / dead-man's switch:** the backup job pings an external
    watchdog (e.g. healthchecks.io, or a self-hosted equivalent) *on success
    only*; the watchdog alerts when the expected ping fails to arrive. This
    catches the failure modes local checks can't — the box being down, the timer
    never firing, the network being gone. Alert must land somewhere we actually
    see it.
  - **Freshness alert:** independently assert the newest snapshot is younger than
    ~2× the interval (`restic snapshots` age check), so a job that "succeeds" but
    stops producing snapshots is caught.
  - **Restore drill:** periodic `restic restore` of `/var/lib/gio-ca` to a scratch
    dir + verify the keys decrypt — proves the repo is actually recoverable.

## Pre-flight (prerequisites)

- [x] Devshell tooling — `age`, `age-plugin-yubikey`, `step-cli`, `paper-age`,
  `qrencode` in `nix/devshell.nix`.
- [x] **Break-glass hardware keys** — resident FIDO2 `ed25519-sk` on YubiKey A
  and B (`break-glass-a`/`-b`). *Still TODO: put both pubkeys in every host's
  `authorized_keys` before any CA sshd change (the safety gate).*
- [x] YubiKey age identities A + B (`general_a`/`general_b`).
- [x] Paper recovery age key — generated, `paper-age` printed to the safe, pubkey
  saved (`ca-root-recover.pub`).
- [x] Recipient set assembled (`ca-recovery-recipients.txt`) = YubiKey A + B +
  paper recovery.
- [x] USB stick — used in the ceremony (now the offline key backup, in the safe).
- [~] DNS: `ca.gio.ninja → strontium` CNAME added
  (`modules/hosts/carbon/dns-aliases.nix`); `strontium.gio.ninja` A auto-derives
  from `host.network`. **Not yet deployed to the DNS servers** (gallium/rhodium).

## ✅ Ceremony complete — Phase-1 keygen done

Params used: EC P-256; root `Gio Homelab Root CA` (20y); intermediate
`Gio Homelab Intermediate CA` (10y). Backup decryption verified via YubiKey A.
Runbook: `docs/archive/ca-ceremony-runbook.md`.

**Where the key material lives now:**
- **strontium `/var/lib/gio-ca/`:** `intermediate.key` + `intermediate.crt`,
  `root.crt` (public anchor), `ssh_user_ca`(+`.pub`), `ssh_host_ca`(+`.pub`).
- **USB (offline, in safe):** `*.age` of all four private keys (encrypted to the
  recovery set) + the public certs + the root `paper-age` PDF.
- **safe:** printed root-key paper.
- **Root private key** exists ONLY in the USB age backup + paper — wiped from
  strontium's tmpfs. `ca-recovery-recipients.txt` is on cadmium (`tmp/ca-setup/`).

## Open decisions / to flesh out

- [x] **Board = Pi 3B+** (confirmed). aarch64 build via binfmt emulation on
  cadmium or an aarch64 builder.
- [ ] **CA concrete build:** the `ca.json` (ssh block + OIDC & JWK provisioners),
  host-cert mint/renew mechanics, and the fleet-wide sshd cutover to the new CA.
  (Decided: **replace** the `modules/aspects/ssh` CA; SSH-first; keys on-disk in
  Phase 1.)
- [ ] **Migration path** fleet.secrets/credsync → the new CLI + `gio.credentials`
  assertion, per-secret cutover; fold in the pending `_`↔`-` rename audit.
  - Also migrate strontium's **manually-created** credstore blobs:
    `restic-password` and `restic-s3-credentials` (garage S3 as an AWS
    shared-creds INI file, via `AWS_SHARED_CREDENTIALS_FILE`), hand-`systemd-creds
    encrypt`ed into `/usr/lib/credstore.encrypted/`. Host/TPM-bound → re-create by
    hand on any reinstall until migrated to age.
- [ ] **`gio.credentials` verification wiring:** bolt the manifest assertion onto
  the existing module vs a thin new layer both feed into.

Decided (secrets): no agenix (custom nushell CLI); secrets fully out-of-band
(not a flake input/submodule — those land in the store); hosts aren't recipients
(decrypt-locally, pipe to `systemd-creds` on the host); blobs at
`/usr/lib/credstore.encrypted`; names-only `secrets.nix` manifest, attrset of
lists; `recipients.txt` at repo root.
- [ ] **Generated secrets** — two kinds:
  - (a) **dev-generatable** (wg keypairs, CA signing keys, etc.) → generate on the
    dev machine, `age`-encrypt once, `push`.
  - (b) **host-generated** — values that can only be produced on the host and
    can't be made on the dev machine (e.g. SSH host keys, keys a service mints on
    first run). For these we may need a **pull/import** path: capture the
    host-generated value and encrypt it *back into* the offline store (to the
    recipient set) so it's backed up, re-pushable, and recoverable. Not yet
    designed — effectively the reverse of `push`.
- [ ] **Bootstrapping order:** host SSH keys as agenix recipients; first-deploy
  chicken-and-egg on a fresh host.
- [ ] **OS on the Pi:** NixOS (aarch64, cross/emulate) vs plain Pi OS running just
  step-ca (decoupled from the Nix world). Leaning NixOS.
- [x] **SPEC.md:** archived to `docs/archive/carbon-gallium-den-migration-spec.md`
  (den-migration spec, a now-done project). The mTLS reversal lives here, not there.
- [ ] **Fit into DNS / Consul / monitoring** for the new node.

## Non-goals / deferred

- mTLS enforcement (revisit only if simpler).
- bcachefs on the Pi (fun experiment for a spare x86 box, not this node).
- User-account secrets via the systemd-creds bridge (module limitation).

## Related

- `docs/archive/fleet-secrets-design-superseded.md` — the credsync system being superseded.
- `modules/aspects/secrets/` — current `fleet.secrets` impl.
- `modules/aspects/ssh/` — the SSH aspects (step-ca host-cert renewal + CA trust +
  access grants; the hand-rolled CA/signer was removed in the cutover).
- `MIGRATION.md` — carbon disk incident, backup/monitoring follow-ups, the step-ca
  cutover cleanup, and the OIDC / user-cert phase.
- `docs/archive/carbon-gallium-den-migration-spec.md` — the old mTLS/step-ca clause.
- Prototype: `github.com/korfuri/agenix-systemd`, issue `ryantm/agenix#123`.
