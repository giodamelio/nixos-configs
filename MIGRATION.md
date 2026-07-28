# Current migration & transition

The single running checklist for the in-flight fleet transition. General
(non-transition) fleet cleanups live in `tmp/TODO.md`; finished projects in
`docs/archive/`.

In scope here:
- **Rebuild carbon** — disk swap runbook + post-boot verify (was `migration-plan.md`).
- **Carbon-incident followups** — automated backups + disk/ZFS health monitoring
  (the TOP-PRIORITY items the failing disk earned).
- **step-ca / SSH cutover** — the teardown is done in-repo; remaining = deploy it,
  enroll carbon + rhodium, then the OIDC / user-cert phase.
- **Secrets** — agevault (design in `docs/pi-ca-secrets-plan.md`) becomes the only
  delivery path; `fleet.secrets` is cut down to use-sites and systemd emission.
  Generators, `origin`, `copyTo`, and credsync all go. See "Retire the delivery
  half of fleet.secrets" — it is a prerequisite for the carbon rebuild.
- **strontium CA** — stood up + all four live hosts enrolled (done; see
  `docs/pi-ca-secrets-plan.md` for the design).
- **Blueprint retirement** — the den host migration is **done** (all six NixOS
  hosts). What is left under `nix/` is packages, lib, devshell, formatter,
  templates, and darwin. Staged teardown in "Phase 13".

## Where this stands

Written 2026-07-30, for picking this up cold.

**carbon has been down for four weeks** (disk died 2026-07-02). Everything else in
the fleet is running. The whole transition is now shaped around getting it back,
and several unrelated tracks were pulled onto that critical path because they
touch the same code.

### The critical path

```
Open the age bundle --> fleet.secrets teardown --> carbon rebuild --> gallium deploy
     (Phase 0.1)            (repo work)             (Phases 1-12)     (Phase 12)
```

Nothing else matters until carbon is back. Four gates, in order:

1. **The age bundle opens.** `tmp/carbon-creds-backup.tar.age` holds all 37 of
   carbon's secrets. Several are unrecoverable if it does not open —
   `pocket_id_encryption_key`, `solidtime_app_key`, `grafana_secret_key`,
   `paperless_env` encrypt data that survives in the database but becomes
   unreadable without them. **Untested as of writing.**
2. **The `fleet.secrets` teardown lands.** agevault becomes the sole delivery path.
3. **carbon rebuilds.** 12 phases, staged bring-up in 5 waves.
4. **gallium catches up.** 6 blob renames plus a deploy, which also lands the
   step-ca teardown it has been owed.

### Track status

| Track | State |
| --- | --- |
| strontium CA | Done. Stood up, all four live hosts enrolled. |
| agevault CLI | Done. Built, tested, strontium's three creds live on it. |
| den host migration | Done. All six NixOS hosts. |
| step-ca / SSH cutover | Done in repo, undeployed. Four live hosts still trust both CAs; carbon needs a fresh enroll on rebuild. |
| carbon rebuild | Planned, not started. Machine is assembled with the new SSD. |
| fleet.secrets teardown | Planned, not started. |
| Backups + disk health monitoring | Not started. The two TOP-PRIORITY items the incident earned. |
| Blueprint retirement (`nix/`) | Not started. Phase 13. |
| OIDC user certs | Future, gated on Pocket ID — which lives on carbon. |

### Risk register

**gallium holds the only copy of carbon's data.** The old drive is dead, not
shelved. `tank/rescue/carbon-*` is it. Every restore step in the runbook is
read-only against gallium, and `zfs destroy -r tank/rescue` is the last item in
Phase 12, gated on carbon producing its own verified backup.

**The working tree is far ahead of `origin/main`.** ~80 uncommitted files, local
`main` behind that, `origin/main` ~10 behind local `main`. carbon and gallium both
run comin against `origin/main`. If carbon boots with comin live it converges onto
a config with the old SSH CA, no `nfs.endpoint`, and **gradient unmasked**. Phase
0.4 disables comin for the rebuild window; Phase 12 re-enables it only after main
is pushed.

**The cause of the incident is still not fixed.** `zfs-backup` was enabled on
carbon and replicated nothing, and nothing flagged it. Until backups run *and* are
restore-drilled, and pool health actually alerts, the fleet is one drive away from
repeating this.

### Settled — do not relitigate

agevault as sole delivery. Generators and `origin` deleted. Named blobs with
consumer-side fixes for the three renames. snake_case names only. Staged bring-up
in waves. Single SSD now, mirror later.

### Still open

- **Mirror `tank`.** This document's own #1 lesson. A `zpool attach` of an M.2,
  no reinstall needed — but "later" is what produced the incident.
- **Three rename call sites** need real design: `wg-priv` (trivial),
  `consul_encrypt.json` (needs the extension for consul's parser),
  `secrets.json` (upstream hardcodes it).
- **gradient stays masked** through wave 5 and beyond, until garage and its
  secrets settle.
- **carbon is not on the heartbeat** — the only server that is not. Needs a
  `healthcheck_url` in agevault plus a Healthchecks.io check.

- **strontium does not evaluate.** `modules/hosts/strontium/default.nix` declares
  `fleet.credentials.needs = ["gatus_push_token"]`, but that credential is not in
  strontium's manifest entry — the host has only `healthcheck_url`,
  `restic_password`, `restic_s3_credentials`, `step_ca_provisioner_password`. A
  leftover of the Gatus teardown; Gatus is gone, so dropping the line is probably
  right. The host cannot build until then. (Found 2026-07-31.)

- **gallium's atticd is broken, fix written but undeployed.**
  `services.atticd.environmentFile` pointed at
  `/run/credentials/atticd.service/attic-envfile`, which cannot work:
  systemd loads `EnvironmentFile=` when it spawns each `Exec*` line, *before* that
  invocation's credentials exist, so the path is always missing and the unit
  restart-loops with `Failed to load environment files`. Confirmed on gallium with
  a minimal `systemd-run` reproducer. `modules/hosts/gallium/attic.nix` now stages
  the credential into a `RuntimeDirectory` via `ExecStartPre` and reads
  `EnvironmentFile=-/run/atticd/env`. Not yet deployed.

- **gallium is ~7 weeks behind.** Running generation 117 (2026-07-06) as of
  2026-07-31. A `switch` lands everything accumulated since, not just the atticd
  fix — run `nix store diff-closures /run/current-system ./result` first.

### Where to start

Step 1 of the teardown — `_lib.nix`, `schema.nix`, `_expand.nix` — is pure repo
work, deploys nothing, and gates on `nix eval` plus `prek run -a`. It is the
largest chunk and the only one that cannot break anything while carbon is down.

Open the age bundle first. It is a two-minute check that invalidates the entire
plan if it fails, and everything downstream assumes it works.

## HISTORICAL — carbon's disk failure (found 2026-07-02)

> Kept for context. The evacuation below is **done**; the drive is dead and out of
> the machine. Do not follow these steps — the live procedure is
> "Rebuild carbon (disk swap) — RUNBOOK".


Surfaced during post-reboot verification: carbon was glacially slow (`systemctl`/
`journalctl` taking forever, caddy start-timeout, session scope failing).

**Root cause — hardware, not config:**
- `tank` pool is **DEGRADED**, **single disk, no redundancy**:
  `ata-ST1000LM024_HN-M101MBB_S31LJ9HF509418-part2` — "too many errors" (an
  ST1000LM024, a known-bad 1TB 2.5" HDD, already forcing `brokenfpdmaaa`/`nolpm`).
- Throughput ~**1.3 MB/s**; I/O pressure stalls *all* tasks ~66% of the time
  (`/proc/pressure/io full avg300≈66`); `txg_sync` wedged in D-state. CPU/mem
  pressure ~0 — it is purely the dying disk.
- **There were ZERO backups of carbon on gallium** — the `zfs-backup` aspect
  replicated nothing. This is its own failure (investigate below).

**Actions, in order (data first — it is unredundant and unbacked-up):**
1. **Do NOT reboot carbon** until data is evacuated — it may not re-import.
2. Rescue snapshot already taken: `tank@rescue-evac` (recursive).
3. Stop the write load (windmill runs `bun install`; frees the disk for fast
   sequential reads): `sudo podman stop windmill_worker windmill_worker_native grist`
4. Evacuate the irreplaceable datasets to gallium (skip `tank/nix` — rebuildable;
   run in tmux). From **inside carbon**:
   ```bash
   ssh server@gallium.gio.ninja 'sudo zfs create -o mountpoint=none tank/rescue 2>/dev/null; echo ready'
   sudo zfs send    tank/root@rescue-evac     | ssh server@gallium.gio.ninja 'sudo zfs recv -s -u tank/rescue/carbon-root'
   sudo zfs send    tank/home@rescue-evac     | ssh server@gallium.gio.ninja 'sudo zfs recv -s -u tank/rescue/carbon-home'
   sudo zfs send -R tank/vms@rescue-evac      | ssh server@gallium.gio.ninja 'sudo zfs recv -s -u tank/rescue/carbon-vms'
   sudo zfs send    tank/microvms@rescue-evac | ssh server@gallium.gio.ninja 'sudo zfs recv -s -u tank/rescue/carbon-microvms'
   ```
   (Needs carbon→gallium SSH — use `ssh -A` agent forwarding, or run the whole
   pipeline from cadmium: `ssh server@carbon '…send…' | ssh server@gallium '…recv…'`,
   which is safer since it doesn't lean on carbon's dying disk.) Resume a broken
   transfer via `receive_resume_token` + `zfs send -t <token>` — don't restart.
   Verify: `ssh server@gallium.gio.ninja 'sudo zfs list -r tank/rescue'`.
5. **Replace the disk** (`zpool replace` or reinstall + `zfs recv` back). Note the
   credstore blobs under `tank/root` are TPM-bound to carbon and won't decrypt on
   new hardware — those secrets get re-provisioned; postgres/app data is portable.

**Do NOT** run a scrub or any heavy I/O on the failing drive. `zpool clear tank`
only resets counters (errors return).

**Investigate:** why `zfs-backup` (`modules/aspects/server/zfs-backup.nix`)
replicated nothing carbon→gallium — a silent backup gap on an unredundant host is
as serious as the disk itself.

## 🔴 TOP-PRIORITY follow-ups (from the carbon disk incident)

These two are the reason a failing disk turned into a near-total-data-loss event.
Neither is optional.

- [ ] **Automated backups fully running AND tested end-to-end.** `zfs-backup` was
  "enabled" yet produced zero carbon→gallium replication and nothing flagged it.
  Requirements to call this done: (1) replication actually runs on a schedule and
  lands snapshots on gallium; (2) an alert fires on failure OR staleness (last
  successful backup age), not just on error; (3) a real **restore drill** — `zfs
  recv` a dataset onto a scratch target and verify the data. A backup you have
  never restored from does not count.
- [ ] **Disk + ZFS pool health monitoring with alerting.** The pool went DEGRADED
  ("too many errors") and the first symptom anyone saw was the box grinding to a
  halt. Add monitoring that pages *before* that: `zpool status` state
  (DEGRADED/FAULTED, read/write/cksum error counts), periodic scrub + scrub
  results, and SMART attributes (reallocated/current-pending/offline-uncorrectable
  sectors — note `smartmontools` isn't even installed on carbon). Surface via
  gatus/prometheus/netdata with a notification path. Ideally also move critical
  single-disk pools onto redundancy (mirror) so one bad drive isn't fatal.

Deploy order: run `./snapshot-carbon.sh` + `./snapshot-gallium.sh`, then
`./deploy-boot.sh`, then reboot **both hosts together**:

```bash
ssh server@carbon.gio.ninja  sudo reboot
ssh server@gallium.gio.ninja sudo reboot
```

## Retire the delivery half of fleet.secrets

Decided 2026-07-30. agevault becomes the only way a secret value reaches a host.
`fleet.secrets` keeps use-sites and systemd emission and loses everything about
producing and moving values: generators, `origin`, `copyTo`, and the whole
credsync push apparatus.

This is a prerequisite for the carbon rebuild below, not a follow-up. carbon's 37
secrets are re-delivered from agevault during the restore, so the rebuild is the
cheapest moment to land it.

### Why the swap is a no-op at the blob level

Both tools write the same file, to the same directory, with the same command:

```
credsync.nu:88    $incoming | ^systemd-creds encrypt ...(creds-args) "--name=" - $tmp
agevault.nu:242   systemd-creds encrypt --name="$name" - "$dir/.$name.tmp" < "$tmp"

_expand.nix:30    credstoreDir = "/usr/lib/credstore.encrypted"
agevault.nu:67    $env.AGEVAULT_CREDSTORE_DIR? | default "/usr/lib/credstore.encrypted"
```

`fleet.secrets` never cared who wrote the blob. The provision units are gated on
`ConditionPathExists=!<blobPath>`, and the `.path` / `.target` gating and the
drop-ins only ever read that path.

They differ in one byte: credsync writes **nameless**, agevault writes **named**.
A nameless blob loads under any credential id; a named blob loads only when the
id equals the embedded name. That is the entire reason the three call sites below
need fixing.

### Keep

- use-sites: `unit`, `type` (`credential` / `env-wrapper`), `credential.name` /
  `.source` / `.encrypted`, `env-wrapper.variable`, `restartOnChange`, `upholds`
- the per-site credential drop-ins and the per-unit env-wrapper `ExecStart` rewrite
- `secret-<name>.path` -> `secret-<name>.target` gating (independent of delivery)
- `fleet-secrets-status` + `loginShellInit` warning
- the read-only `fleet.secrets.<name>.path` / `.paths` mirror
- the `missingUnits` warning and the surviving eval-time checks

### Superseded since: `fleet.credentials.unit_wrappers`

Built 2026-07-31 in `modules/aspects/credentials/fleet-credentials.nix`. The
agevault-native successor to the `env-wrapper` use-site type above, so the "Keep"
list shrinks further than originally planned.

```nix
fleet.credentials.unit_wrappers.<unit>.environment.<VAR> = "<credential>";
```

One declaration does all three things: adds the name to `needs` (so the manifest
assertion covers it), attaches `LoadCredentialEncrypted` to the unit, and emits a
`60-credential-env.conf` drop-in that blanks `ExecStart=`, re-points it at a
script exporting the variable from `$CREDENTIALS_DIRECTORY`, and execs the
original command.

Simpler than the `fleet.secrets` version because agevault removes the reasons for
most of its knobs:

- no `credential.name` / `.source` / `.encrypted` — the agevault name **is** the
  blob name, so there is no rename class
- no `restartOnChange` / `upholds` — those exist because credsync pushes new
  values to a running host; agevault delivery is out-of-band

It handles both plain units (`ExecStart` is a string/path/derivation) and modular
services (`ExecStart` is a one-element list — see
`nixos/modules/system/service/systemd/service.nix`, which builds
`ExecStart = [ mainExecStart ... ]`). More than one command is a hard error.

Proven in production on rhodium: `heartbeat.service` runs on it now, verified via
`systemctl status` showing the drop-in attached and ExecStart re-pointed.

Use `needs` instead whenever the service can read a credential path itself
(parseable's `_FILE` vars, garage's `*_file` settings, step-ca, Perses'
`passwordFile` / `credentialsFile`). `unit_wrappers` is only for programs that
can **only** read a value from the environment.

### Delete

| File | Remove |
| --- | --- |
| `secrets/schema.nix` | `scriptType`, `generatorModule`, `generatorType`; `secretModule.origin`, `.generator`, `.copyTo`; the whole `fleet.secretsPush.enable` option |
| `secrets/_lib.nix` | `generatorActive`, `copySet`, `holdsSecret` |
| `secrets/fleet-secrets.nix` | `pushKeys` read, `needsOf`, `reachable`, `pushesEnabled`; the origin/copyTo/generator validation checks |
| `secrets/_expand.nix` | args `credsync` / `pushKeys` / `pushUser` / `enablePushes`; `credsyncExe`, `domain`, `pushKeyName`, `pushKeygenExe`, `forcedCommandExe`, `originSecrets`, `pushOriginsHere`, `hostPushes`, `genExe`, `provisionExe`; the provision units, push units, push timers, `credsync-push-keygen`, and the `users.users.<pushUser>.openssh.authorizedKeys` block |
| `homelab.toml` | the `[credsync_push_keys]` block |
| `modules/packages/credsync/` | the whole package: `.nu`, `.nix`, `_test.nix` |

`heldSecrets` gets redefined from "origin or in the copy set" to simply "has an
enabled use-site on this host". `statusMessage` collapses to one message, since
every secret is manual now.

Dropping the provision units loses nothing: they were redundant three ways over.
`fleet-secrets-status` writes the login warning, the `.path` / `.target` pair
handles ordering, and a unit with `LoadCredentialEncrypted=` on a missing blob
fails on its own.

### Rewrite the tests

- `secrets/_test.nix` is a two-VM push test today. Rewrite as a single node:
  pre-seed a blob into the credstore, then assert the drop-in loads it, the
  target gates, the env-wrapper exports, and the login warning clears.
- `secrets/check.nix`: drop the `holds-*` eval tests (they cover `holdsSecret` /
  `copySet`); update `name-dot-rejected` / `credid-dot-ok` for the new regexes.
- `modules/checks/nfs.nix` drives the WG key exchange through `secret-push-*`.
  Rewrite to pre-seed both hosts' keypairs.

### Rename everything to snake_case

Do it in the same pass — the delete already touches every declaration.

```nix
nameRe         = "[a-z0-9_]+";     # was [a-z0-9-]+
credentialIdRe = "[a-z0-9._]+";    # was [a-z0-9.-]+
```

43 secrets across two hosts: carbon 37, gallium 6. No other host uses the
registry.

carbon's 37 are free — they arrive from agevault under whatever name you pick.

gallium's 6 are six `mv`s in `/usr/lib/credstore.encrypted/`, because credsync
wrote them **nameless**: there is no embedded name to invalidate, so no
re-encryption and no regeneration. That matters specifically for
`garage-rpc-secret` and `wg-nfs-priv-gallium` — if a rename made a provision unit
fire instead, it would mint new values and break garage and the mesh.

### Fix the three rename call sites

Named blobs mean `credential.name` must equal the secret name, or the load fails.

| Secret | Id today | Fix |
| --- | --- | --- |
| `wg_nfs_priv_<h>` | `wg-priv` | drop the override at `aspects/nfs/secrets.nix:23`; point the `wg-nfs` unit at the full name |
| `consul_encrypt` | `consul-encrypt.json` | consul parses `-config-file` by extension. Try `-config-format=json` to drop the suffix; else materialise `%d/consul_encrypt` at a `.json` path in an `ExecStartPre` |
| `zwavejs_secrets` | `secrets.json` | upstream hardcodes `%d/secrets.json` in its `ExecStartPre`. Override it to read `%d/zwavejs_secrets` (you already `mkForce` its `LoadCredential`) |

`aspects/nfs/secrets.nix:42` sets `credential.name = wgPubName h`, which already
equals the secret name. Redundant; drop it.

Ordering trap: gallium's `consul_encrypt` blob is nameless, so the `.json` rename
keeps working there even after the snake_case `mv`. It breaks the moment agevault
re-pushes it as a named blob. Land the consul fix before pushing that secret.

Gradient's ~13 hand-written mappings at `gradient.nix:276-291` are a special case.
Its credential ids are generated by gradient and mix both separators, so they
cannot be expressed as `fleet.secrets` names under `[a-z0-9_]+`:

```
gradient_worker_4f7f7bfb-6013-405a-9a5f-fc98449725d7_token
gradient_integration_forgejo-inbound_secret
gradient_action_deploy-webhook_token
```

That does not matter, because those `LoadCredentialEncrypted=` directives are
**hand-written and never pass through `nameRe`**. Drop those 13 from
`fleet.secrets` entirely, store them in agevault under their exact credential ids,
and let gradient reference them with no rename at all — id == blob name ==
embedded name. carbon's credstore already carries blobs under exactly those names
from the pre-`fleet.secrets` era, so the values are in the bundle.

Gradient stays masked, so this is not on the critical path.

### What you are trading away

Adding a host to the NFS mesh costs nothing today: `secretsFor h` mints the
keypair and wires the pub half to every peer. Afterwards it costs a `wg genkey`,
two `agevault write`s, and a manifest regen per new host. With two hosts on the
mesh that is an acceptable trade, but it is a real one.

Nothing is lost for carbon. All three generated secrets — `consul_encrypt`,
`wg_nfs_priv_carbon`, `wg_nfs_pub_carbon` — need their **existing** values
recovered from the age bundle rather than freshly minted, because gallium holds
copies of two of them and regenerating would split the consul cluster or break
the mesh. The generators would have been bypassed regardless.

### Sequence it

The hard constraint: gallium is live and holds the only copy of carbon's data.
Nothing here may disturb it before the restore completes.

1. **Repo only, nothing deployed.** Teardown, snake_case rename, the three call
   sites, test rewrites. Gate on `nix eval` of every host plus `prek run -a`.
2. **Load agevault.** carbon's from `tmp/carbon-creds-backup.tar.age`, gallium's 6
   from its live credstore, all under snake_case names. `agevault generate-toml`.
   **Read "Pick the live blob, not its twin" below first** — the bundle contains
   both live values and stale same-name orphans.
3. **Rebuild carbon** (runbook below). `agevault push carbon` delivers all 37.
4. **gallium last.** `mv` its 6 blobs to snake_case, then deploy.

Steps 3 and 4 decouple cleanly: blob names are local filenames, so carbon can run
snake_case while gallium still runs hyphenated. What has to match across hosts is
the *values* (gossip key, WG keys), not the names. gallium keeps serving the
restore on its current generation throughout.

### Pick the live blob, not its twin

Verified against the bundle 2026-07-30. carbon's credstore holds **77 blobs**, and
many secrets appear **twice** under different names. They are not copies:

| Live blob (what actually gets loaded) | Stale twin | Delta |
| --- | --- | --- |
| `gradient-org-private-key` 119 B | `gradient_org_default_private_key` 399 B | different value |
| `gradient-cache-signing-key` 103 B | `gradient_cache_main_signing_key` 45 B | different value |
| `zwavejs-secrets` 415 B | `secrets.json` 262 B | different value |
| `gradient-jwt-secret` 65 B | `gradient_jwt_secret` 64 B | 1 byte |
| `gradient-crypt-secret` 65 B | `gradient_crypt_secret` 64 B | 1 byte |
| `gradient-metrics-token` 45 B | `gradient_metrics_token` 44 B | 1 byte |
| `gradient-forgejo-access-token` 41 B | `gradient_integration_forgejo-outbound_token` 40 B | 1 byte |
| `consul-encrypt` 58 B | `consul-encrypt.json` 59 B | 1 byte |

The rule is consistent: **the hyphenated blob is live** — it is what
`fleet.secrets` and gradient's hand-written directives load via the rename — and
the underscore or `.json` twin is a **pre-`fleet.secrets` leftover**.

`zwavejs-secrets` proves it. 415 B is the fixed nested `securityKeys` shape from
the zwave bugfix; the 262 B `secrets.json` is the old flat snake_case form that
broke. Restoring the twin would silently reintroduce that bug.

So when loading agevault: take the **value** from the hyphenated blob, store it
under the **snake_case name**. Use `agevault write <host> <name> -` (byte-exact
stdin), never retype. The 1-byte deltas are trailing newlines and matter for
anything parsed strictly.

The remaining orphans are safe to skip: `apiToken`, `attic-apps-cache-config`,
`caddy-cloudflare-config`, `ca-password` and `intermediate_ca_key` (the retired
hand-rolled SSH CA), `cronitor-api-key`, `discord_token`,
`forgejo-runner-{token,build-env}`, `hammond_openrouter_api_key`, `mealie_token`,
`paperless-config`, `telegraf-postgres-passfile`, `test-secret`,
`wg-nfs-private-key`, `wireguard-wg0-private-key`, `credsync-push-key`.

**Keep `syncoid-ssh-key`** (411 B, an ed25519 key). It is the replication identity
for the ZFS backups that silently never ran — needed for the TOP-PRIORITY backup
follow-up.

## Rebuild carbon (disk swap) — RUNBOOK

> Restore carbon onto its new SSD from the gallium evacuation. Rewritten
> 2026-07-30; the original was drafted mid-incident and several of its
> assumptions have since gone stale (see "What changed" below).

Same physical machine (HP EliteDesk 800 G2 DM) with a fresh ~512 GB SATA SSD in
the 2.5" bay. Same TPM, same host identity — that is what makes this a
**same-machine restore** rather than a fresh host, and it is why ~25 credstore
secrets can come back untouched instead of being re-provisioned by hand.

### gallium is the ONLY copy

The old `ST1000LM024` is **dead** — it is not a rollback. `tank/rescue/carbon-*`
on gallium is the single surviving copy of carbon's data. Therefore:

- **Never** `zfs destroy` anything under `tank/rescue` until carbon is verified
  green *and* has produced its own fresh backup.
- Every restore step is a **read** from gallium (`zfs send`). Nothing in this
  runbook writes to or reconfigures gallium.
- If a receive goes wrong on carbon, just re-run it. The source is untouched.

### What changed since the original runbook (the traps)

1. **`fleet.secretsPush.enable` now defaults to `false`**
   (`modules/aspects/secrets/schema.nix:180`) — the credsync push units are OFF
   fleet-wide. The old claim "credsync re-pushes the new wg pubkey to gallium
   automatically" is **no longer true**. If carbon's wg-nfs private key does not
   survive the restore, a *new* keypair is generated and the mesh stays broken
   until the pubkey is hand-relayed. Keep `relay-wg-nfs-keys.sh` until the mesh
   is confirmed up.
2. **comin would undo the install.** carbon includes `den.aspects.comin`, polling
   `github.com/giodamelio/nixos-configs` **main**. `origin/main` is ~16 commits
   behind the working tree; converging on it would restore the old SSH CA data,
   drop `nfs.endpoint`, and **unmask gradient**. comin is therefore disabled on
   carbon for the rebuild window (step 0.3) and re-enabled only once main has
   caught up (Phase 12).
3. **The step-ca cutover happened.** carbon's old host cert is no longer trusted
   fleet-wide; it needs a fresh enroll (Phase 11).
4. **Postgres major is a silent-data-loss risk.** The new build wants
   `/var/lib/postgresql/**17**`. If the restored root holds a different major,
   every database comes up *empty and healthy-looking*. Checked in 8.3.
5. **carbon is 100% on the old credsync `fleet.secrets`** — `secrets.toml` has no
   carbon entries at all. The whole secrets story rests on the restored credstore
   blobs decrypting. Provisioning is gated on `ConditionPathExists=!<blob>`
   (`_expand.nix:301`), so restored blobs are left alone and nothing silently
   regenerates behind you.

### Secrets: agevault delivers, fleet.secrets wires

carbon's 37 secrets come back from agevault, not from the restored credstore. The
full teardown is in "Retire the delivery half of fleet.secrets" above; land that
work before starting Phase 1.

Two consequences for this runbook:

- **The TPM stops being a gate.** Phase 8.4 drops from blocking to informational.
  You still want `tank/root` for postgres, `/var/lib` state, `machine-id`, and the
  uid maps — but the credstore itself is disposable, because `agevault push carbon`
  rebuilds it.
- **Gate 0.2 becomes load-bearing instead.** `tmp/carbon-creds-backup.tar.age` is
  now the source of truth for every carbon secret. Several are unrecoverable if it
  will not open, even with the database intact: `pocket_id_encryption_key`,
  `solidtime_app_key` (Laravel `APP_KEY`, encrypts DB columns), `grafana_secret_key`,
  `paperless_env`. Open it first, before anything else in Phase 0.

`caddy_cloudflare_api_token` is **not** a `fleet.secret` — it is hand-wired at
`aspects/server/reverse-proxy.nix:128`. It has to be in agevault too, and it is a
wave 1 dependency.

### Key facts that shape the steps

- **disko declares 4 datasets:** `reserve` (5 G resv, mnt none), `root` (`/`,
  legacy), `nix` (`/nix`, legacy), `home` (`/home`, legacy) on a zstd `tank`,
  plus a 1 G ESP at `/boot`. (`modules/hosts/carbon/disko.nix`)
- **`vms`, `vms/hammond`, `microvms` are NOT in disko** — runtime-created. `zfs
  recv` recreates them from the gallium copies. (`microvms` has no consumer in
  the den config today; restore it anyway, it is small.)
- **`/nix` and `/boot` were never backed up** (by design) — regenerated by the
  install.
- **Plain `zfs send` did not carry `mountpoint`** — set it after every recv.
- **The installer never evaluates this flake.** Both the disko script and the
  system closure are built on cadmium and `nix copy`'d over; 80+ flake inputs on
  a live-ISO tmpfs is a bad time.

### What the restored `tank/root` brings back

`/etc/ssh` (host keys) · `/etc/machine-id` ·
`/var/lib/systemd/credential.secret` · `/usr/lib/credstore.encrypted` (all
credsync blobs) · `/var/lib/nixos/{uid,gid}-map` (stable uids — matters for the
`nfs-*` groups) · `/var/lib/postgresql` · `/var/lib/containers` (podman images
and the **podman secrets** grist references) · `/var/lib/openbao` (raft; comes up
**sealed**, unseal by hand) · all other `/var/lib` service state.

Verified present against the snapshot on 2026-07-30 (`./peek-rescue-root.sh`).
The host key matches `default.nix:19` byte for byte, `credential.secret` dates
from the original Apr 2024 install, and the uid/gid maps are from 2026-07-01
17:16 — the day before the disk died.

`/var/lib/private` also carries state for four **retired** services —
`cloudflare-dyndns`, `crowdsec`, `rustmailer`, `wgautomesh`. None exists in
either config tree (crowdsec only as commented-out code in
`nix/hosts/carbon/hooks.nix`), so they restore as dead directories. Not a gap;
worth a cleanup pass someday.

---

## Phase 0 — Pre-flight (on cadmium, before touching carbon)

### 0.1 GATE: open the secrets bundle — PASSED 2026-07-30

> 77 entries, zero missing, no zero-byte files, all four unrecoverable secrets
> present. Every credstore blob made it into the bundle; nothing failed to
> decrypt during the export. Re-run any time to re-verify.

Do this before anything else. `tmp/carbon-creds-backup.tar.age` is now the source
of truth for all 37 of carbon's secrets, not a fallback — the restored credstore
is disposable once agevault owns delivery.

It is **passphrase-encrypted** (scrypt), not key-encrypted, so it needs the
passphrase from the password manager:

```bash
./verify-creds-bundle.sh
```

Decrypts to a listing only — no plaintext ever reaches disk. It diffs the
contents against the 42 blobs carbon's credstore is expected to hold, flags
zero-byte entries, and separately checks the four that cannot be regenerated even
with the database intact: `pocket-id-encryption-key`, `solidtime-app-key`,
`grafana-secret-key`, `paperless-env`.

The expected set is **42, not 37**: the 39 `fleet.secrets` carbon holds (37 it
provisions, plus `garage-metrics-token` and `wg-nfs-pub-gallium` received from
gallium), plus three hand-wired blobs that are not `fleet.secrets` at all and are
easy to miss — `caddy-cloudflare-api-token`, `gradient-cache-netrc`, and
`credsync-push-key` (that last one dies with the teardown, so its absence is
fine).

If this does not open, stop and reassess the whole plan.
**Do not proceed past this gate.**

### 0.2 GATE: verify the rescue data is complete — PASSED 2026-07-30

> All four datasets carry `@rescue-evac`, no partial receives, nothing set to
> auto-prune `tank/rescue`, gallium ONLINE at 28% with 15.6 T free.

```bash
./verify-rescue-data.sh
```

Read-only; it observes gallium via sudo and changes nothing. Every
`receive_resume_token` must be `-` (no partials) and each of
`carbon-{root,home,vms,microvms}` must carry an `@rescue-evac` snapshot.

It also checks whether anything is set to auto-prune `tank/rescue`. The only copy
of carbon's data must not be sitting on a retention clock.

**Do not proceed past this gate.**

### 0.3 Land the fleet.secrets teardown

Steps 1 and 2 of "Retire the delivery half of fleet.secrets" above: the repo
change (generators, `origin`, `copyTo`, credsync, snake_case rename, the three
rename call sites, test rewrites), then load agevault with carbon's 37 from the
bundle plus `caddy_cloudflare_api_token`, and run `agevault generate-toml`.

Gate on `nix eval` of every host plus `prek run -a`. Nothing is deployed here.

### 0.4 Disable comin on carbon (trap #2)

In `modules/hosts/carbon/default.nix`, comment `den.aspects.comin` out of
`den.aspects.carbon.includes` with a TEMP note pointing at Phase 12.

### 0.5 Add the staged bring-up mask

Create `modules/hosts/carbon/staged-bringup.nix` — same masking pattern as
`gradient-disable.nix` (`systemd.services.<unit>.enable = lib.mkForce false`),
with one wave uncommented at a time. Wave contents are in Phase 10.

### 0.6 Build the installer ISO

`nix/packages/custom-installer-iso.nix` still evaluates clean against current
nixpkgs (26.11) — verified 2026-07-30. Checked what the `install-iso` format
already gives us, so we don't add what's there:

| Need | Status |
| --- | --- |
| ZFS | **already there** — `boot.supportedFilesystems.zfs = true`, zfs 2.4.3 on kernel 6.18.38 (`nixpkgs/nixos/modules/profiles/base.nix:66`) |
| `networking.hostId` | **already there** — `8425e349` (≠ carbon's `3a06cc0b`, so no conflict) |
| sshd running at boot | **already there** — `install-iso.nix` forces `sshd.wantedBy = multi-user.target`, `PermitRootLogin = "yes"` |
| `smartmontools` | **already there** |
| root/nixos authorized_keys | **already there** — the package bakes in `homelab.ssh_keys` |
| `pv`, `mbuffer` | **missing — add these** |

So the only edit is:

```nix
environment.systemPackages = [customNeovim pkgs.pv pkgs.mbuffer];
```

Then `nom build .#custom-installer-iso`. **Actually build it in Phase 0**, not at
the console — it is the one step that can fail on a zfs-vs-kernel mismatch, and
you want to find that out on cadmium.

### 0.7 Space check

Measured on gallium 2026-07-30 (gate 0.2), on-disk REFER:

| Dataset | REFER |
| --- | --- |
| `carbon-root` | 22.8 G |
| `carbon-home` | 3.47 G |
| `carbon-microvms` | 5.19 M |
| `carbon-vms` (+ `hammond`) | ~300 K |
| **`tank/rescue` total** | **26.3 G** |

Comfortably inside 512 GB. The uncompressed `pv` totals during the send run
higher (~1.9x, zstd), so do not be alarmed by them — the earlier `~38 G` / `~5.7 G`
figures in `recover.txt` were hand-written estimates, not measurements.

`carbon-vms/hammond` carries a long autosnap chain that stops 2026-02-12; the VM
has been dead since then and `hammond.nix` is only network plumbing now. The
dataset is inert — restore it for completeness, expect nothing from it.

## Phase 1 — Boot the installer

1. JetKVM: mount the ISO as virtual media, boot it.
2. `ip -brief addr` → note the installer IP as `INST`. SSH keys are already baked
   in, so from cadmium `ssh root@$INST true` should just work.
3. Sanity-check the new disk before trusting it:
   ```bash
   lsblk -d -o NAME,SIZE,MODEL,SERIAL
   ls -l /dev/disk/by-id/ | grep -i 'ata-' | grep -v part
   smartctl -a /dev/sdX | head -40
   ```
   Record the stable by-id (`ata-<model>_<serial>`).

## Phase 2 — Point disko at the new disk

On cadmium, in `modules/hosts/carbon/disko.nix`, set
`device = "/dev/disk/by-id/ata-<new-ssd>";`, then:

```bash
git add -A                                            # flakes only see tracked files
nix eval .#nixosConfigurations.carbon.config.system.build.toplevel.drvPath
prek run -a
```

## Phase 3 — Partition and create the pool

Build the disko script on cadmium and ship it — no flake eval on the installer:

```bash
nom build .#nixosConfigurations.carbon.config.system.build.diskoScript
nix copy --to "ssh://root@$INST" ./result
ssh root@$INST "$(readlink -f ./result)"
```

Creates the ESP + zstd `tank` + `reserve`/`root`/`nix`/`home`, mounted at `/mnt`.

## Phase 4 — Make room for the restore

On the installer — unmount, then drop disko's empty root/home so the receives are
plain full-stream creates (cleaner than `recv -F` into a live dataset):

```bash
umount -R /mnt
zfs destroy tank/root
zfs destroy tank/home
```

## Phase 5 — Restore from gallium

Relay through cadmium (it reaches both ends). Run **on cadmium**:

```bash
INST=root@<installer-ip>
recv() { ssh server@gallium.gio.ninja "sudo zfs send $2 tank/rescue/$1@rescue-evac" | pv | ssh $INST "zfs recv tank/$3"; }

recv carbon-root     ""   root
recv carbon-home     ""   home
recv carbon-vms      "-R" vms
recv carbon-microvms ""   microvms
```

Healthy disks on both ends now — minutes, not hours. If one breaks, re-run it;
gallium's copy is read-only in this flow.

## Phase 6 — Fix mountpoints

On the installer (plain sends dropped the property):

```bash
zfs set mountpoint=legacy               tank/root
zfs set mountpoint=legacy               tank/home
zfs set mountpoint=/var/lib/vms         tank/vms
zfs set mountpoint=/var/lib/vms/hammond tank/vms/hammond
zfs set mountpoint=/var/lib/microvms    tank/microvms
```

## Phase 7 — Mount for the install

```bash
nom build .#nixosConfigurations.carbon.config.system.build.mountScript
nix copy --to "ssh://root@$INST" ./result
ssh root@$INST "$(readlink -f ./result)"
```

Mounts `root`→`/mnt`, `nix`→`/mnt/nix`, `home`→`/mnt/home`, ESP→`/mnt/boot`.

## Phase 8 — Verify the restore before installing

Everything below is checkable *before* committing to an install, while re-running
the restore is still free. On the installer:

**8.1 The restore actually landed**

```bash
ls /mnt/etc/ssh/ssh_host_ed25519_key.pub /mnt/etc/machine-id
ls -d /mnt/var/lib/{nixos,systemd,containers,openbao,postgresql}
head /mnt/var/lib/nixos/uid-map          # stable uids for the nfs-* groups
```

**8.2 Host key matches the flake** — compare against `ssh.hostKey` in
`modules/hosts/carbon/default.nix:19`:

```bash
cat /mnt/etc/ssh/ssh_host_ed25519_key.pub
```

**8.3 Postgres major (trap #4) — ANSWERED 2026-07-30, expect a confirmation.**
Verified against the rescue snapshot with `./peek-rescue-root.sh`:

| Major | Size | dirs in `base/` | mtime | running at snapshot |
| --- | --- | --- | --- | --- |
| 15 | 76 M | 5 | 2025-10-30 | stopped |
| 16 | 9.8 M | 3 | 2025-10-31 | stopped |
| **17** | **195 M** | **11** | **2026-07-01 17:18** | **LIVE** (`postmaster.pid`) |

17 holds the data and 17 is what the build wants. 11 dirs = 3 system databases +
8 user ones, matching carbon's DB-backed services. 15 and 16 are upgrade
leftovers. **No package pin and no `pg_upgrade` needed.**

Re-confirm on the installer, then move on:

```bash
ls /mnt/var/lib/postgresql/            # 15 16 17
ls /mnt/var/lib/postgresql/17/base | wc -l   # 11
```

If 17 is somehow absent after the recv, the receive was incomplete — re-run it
rather than reaching for `pg_upgrade`.

**8.4 TPM decrypt smoke test — informational, not a gate.** agevault re-delivers
every secret in Phase 10, so a dead TPM path no longer blocks the restore. Run it
anyway: it tells you whether the old blobs are still readable, which is a useful
cross-check that the bundle from 0.1 matches what was actually on the machine.

```bash
install -Dm600 /mnt/var/lib/systemd/credential.secret /var/lib/systemd/credential.secret
ls /mnt/usr/lib/credstore.encrypted/
systemd-creds decrypt /mnt/usr/lib/credstore.encrypted/wg-nfs-priv-carbon - | head -c 20
```

No `--name=` — credsync wrote these blobs nameless.

**8.5 Blob inventory** — list the old credstore and diff it against the names you
loaded into agevault in 0.3. Anything present here but missing from the vault is a
secret you are about to lose:

```bash
ls /mnt/usr/lib/credstore.encrypted/          # on the installer
grep -A40 '^carbon' secrets.toml              # on cadmium
```

Expect the old hyphenated names on the left and snake_case on the right, so
compare by meaning rather than string equality. `credsync-push-key` is expected to
be orphaned — it dies with the teardown.

This diff is exactly what the `agevault audit` item in `tmp/TODO.md` describes.
Doing it by hand once here is fine; if it is annoying, that is the argument for
building the subcommand.

## Phase 9 — Install

Build the closure on cadmium, copy it over, install from the local store path:

```bash
nom build .#nixosConfigurations.carbon.config.system.build.toplevel
attic push homelab result/                      # optional, warms the cache
nix copy --to "ssh://root@$INST" ./result
ssh root@$INST "nixos-install --system $(readlink -f ./result) --no-root-passwd --no-channel-copy"
```

Writes the bootloader to `/boot` and generates `/etc`. The restored `/var/lib`,
`/etc/ssh`, and credstore are preserved — `nixos-install` does not wipe them.

Then, on the installer:

```bash
umount -R /mnt && zpool export tank && reboot
```

**Unmount the virtual media in JetKVM first** so it boots from the SSD.

## Phase 10 — Staged bring-up

First boot comes up with `staged-bringup.nix` masking everything but the core.
Promote one wave at a time (edit the file, then `nixos-rebuild switch --flake
.#carbon --target-host server@carbon.gio.ninja`), verifying before moving on.
Consul and gatus will show red for anything still masked — expected.

**10.0 Deliver the secrets first.** carbon boots with an empty (or stale-named)
credstore, so wave 1 has nothing to load until you push:

```bash
agevault push carbon
```

Every secret should report `updated`. Re-run it and they should all report
`unchanged` — that is the built-in confirmation that the vault matches the host.

Until this runs, expect `caddy`, `consul`, and `wg-nfs` to fail; they are the
wave 1 credstore consumers. The login banner from `fleet-secrets-status` lists
exactly what is still missing.

**Wave 1 — core (nothing masked).** `sshd` · `systemd-networkd` · `nftables` ·
`zfs-*` / `sanoid` · `wg-nfs` + the two NFS mounts · `postgresql` · `consul` ·
`coredns` · `caddy` · `nats` · `alloy` · `prometheus-node-exporter` ·
`ssh-host-cert-renew`.

```bash
ssh server@carbon.gio.ninja systemctl --failed
ssh server@carbon.gio.ninja 'zpool status tank'         # ONLINE, no errors
./verify-carbon.sh                                       # wg handshake + both NFS mounts
ssh server@carbon.gio.ninja 'sudo -u postgres psql -l'   # every DB present, not empty
```

`caddy` is deliberately in wave 1: it is the first consumer of a credstore blob
(`caddy-cloudflare-api-token`), so it validates the secrets path immediately.
502s from masked backends are expected.

**Wave 2 — identity + NFS consumers.** `pocket-id` (OIDC — everything else
depends on it), then `forgejo` + `forgejo-runner-build` (uses
`/mnt/forgejo-repos`), then the paperless stack (`paperless-*`, `redis-paperless`,
`gotenberg`, `tika` — uses `/mnt/paperless-media`). This wave proves OIDC and
both NFS mounts under real load.

**Wave 3 — observability.** `prometheus` + `prometheus-{postgres,zfs}-exporter` ·
`loki` · `grafana` · `netdata` (parent — gallium's child reconnects on its own) ·
`gatus` · `unifi-poller`.

**Wave 4 — the rest.** `home-assistant` + `zwave-js` + `matter-server` ·
`miniflux` · `mealie` · `solidtime` (+ `phpfpm-solidtime`) · `grist` (quadlet) ·
`windmill-*` + `podman-windmill_worker*` · `restate` (+ its register units) ·
`webhookcatcher` · `eater-of-feeds` · `yesman` · `node-hp-scan-to` · `openbao`
(**unseal by hand after start**).

**Wave 5 — gradient: stays masked.** `gradient-disable.nix` remains until garage
on gallium and the `gradient-*` secrets are settled — and note that the latent
nameless-blob bug described in the `_`↔`-` section below will bite on re-enable.

## Phase 11 — SSH CA re-enroll

carbon's old host cert is no longer trusted. On **strontium**:

```bash
sudo ca-enroll-host carbon
```

Paste the printed command on carbon, then verify per `docs/onboarding-a-host.md`
§7. Until enrolled, `ssh carbon` falls back to a TOFU prompt —
`authorized_keys` login still works, so this does not block the earlier phases.

## Phase 12 — Re-converge and clean up

- [ ] Re-enable `den.aspects.comin` on carbon (undo 0.4) — **only after** the
  working tree is committed and pushed so `origin/main` matches what carbon is
  actually running. Otherwise comin will roll it straight back.
- [ ] **gallium, step 4 of the teardown:** `mv` its 6 credstore blobs to
  snake_case, then deploy. This also lands the step-ca teardown; do
  cadmium/cesium/strontium at the same time.
- [ ] Delete `staged-bringup.nix` once every wave is promoted.
- [ ] Delete `relay-wg-nfs-keys.sh` — it is obsolete either way now, since the
  WG keys come from agevault rather than being generated and pushed.
- [ ] Retire the one-shot rescue scripts: `evac-carbon.sh`, `recover.txt`,
  `export-carbon-creds.sh`. Delete `tmp/carbon-creds-backup.tar.age` only after
  confirming every secret in it reached agevault.
- [ ] **Last:** once carbon has produced its own verified backup, and not before,
  `zfs destroy -r tank/rescue` on gallium.

## Phase 13 — Retire the Blueprint tree (`nix/`)

### Where the den migration actually stands

All six NixOS hosts are on den — cadmium, carbon, cesium, gallium, rhodium,
strontium — each declared in `modules/hosts/<h>/default.nix` and winning over
Blueprint via `flake.nix:22`. The den migration is **done** for hosts.

What is left in `nix/` is not unmigrated hosts. It is:

| Path | Status |
| --- | --- |
| `nix/hosts/{carbon,gallium}` | dead duplicates, shadowed by den; safe to delete now |
| `nix/hosts/thorium` | live — darwin, and `flake.nix` gives Blueprint `darwinConfigurations` outright. Not in `homelab.toml`, so likely dormant: decide whether to migrate or retire |
| `nix/packages/` | live — ~30 packages den does not provide |
| `nix/lib/` | live — `lib` output |
| `nix/devshell.nix`, `nix/formatter.nix` | live — default devShell and treefmt |
| `nix/templates/` | live |
| `nix/modules/{common,home,nixos}` | mixed — some dead duplicates (e.g. `nix/modules/home/claude-code/`), some still feeding thorium and the Blueprint `homeConfigurations` |

So "delete `nix/`" is a migration project, not a cleanup. Stage it.

### Delete immediately (safe once carbon is green)

- `nix/hosts/carbon/`, `nix/hosts/gallium/` — shadowed by den for months.
- `nix/packages/check-drv-drift/` and the baselines in
  `docs/archive/carbon-gallium-migration-tasks/baseline/`.

On the drift gate: it compares a den-built derivation against a Blueprint
baseline to prove the migration was byte-equivalent. The `fleet.secrets` teardown
deliberately changes carbon's and gallium's derivations, so **after that lands a
drift result is expected, not a failure**. The gate has served its purpose and
retires with it. Do not spend time chasing the diff.

### Then migrate what is actually live

1. `nix/packages/` -> `modules/packages/` (den already hosts agevault, credsync,
   herdr-proxy there).
2. `nix/lib/` -> `modules/lib/`.
3. `nix/devshell.nix` + `nix/formatter.nix` -> den equivalents.
4. `nix/templates/` -> wherever den wants them.
5. thorium: migrate to a den darwin host, or retire it. den does not own
   `darwinConfigurations` today, so keeping thorium means keeping Blueprint.

### The trap: do not delete `nix/packages/` before rewriting `flake.nix`

The merge maps over the **Blueprint** side:

```nix
packages =
  builtins.mapAttrs
  (system: bpPkgs: bpPkgs // (fp.packages.${system} or {}))
  bp.packages;

checks =
  builtins.mapAttrs
  (system: bpChecks: bpChecks // (fp.checks.${system} or {}))
  bp.checks;
```

`mapAttrs` iterates `bp.packages`, so if Blueprint stops producing packages the
result is `{}` — and **den's packages silently vanish with it**. Same for
`checks`. Both expressions have to be rewritten to iterate the den side (or a
union of systems) in the same commit that empties `nix/packages/`, or you lose
every package output with no eval error to tell you.

### Finish

Once nothing live remains under `nix/`, drop the `blueprint` input and the whole
`bp` half of `flake.nix`, leaving `fp` as the only output source. Gate the whole
phase on `nix flake show` before and after producing the same output set.

## After the dust settles (the real lessons)

- **Mirror `tank`.** Add an M.2 NVMe in the free slot and `zpool attach` it — no
  reinstall needed, and it permanently retires the failure mode that caused this
  incident.
- **Automated backups running + restore-drilled**, and **disk/ZFS health
  monitoring with alerting** — the two TOP-PRIORITY follow-ups above.
- **Add carbon to `den.aspects.server-heartbeat`** — it is the only server not on
  the heartbeat. Needs a `healthcheck_url` for carbon in agevault (`secrets.toml`
  currently lists only gallium/rhodium/strontium) plus a Healthchecks.io check.

## Verify after reboot (the audited risk areas)

- [x] **wg-nfs tunnel + NFS mounts** — RESOLVED this session. Neither host set
  `nfs.endpoint`, so `wg-nfs.service` died on the unresolvable bare hostname
  `gallium:51830` (`Name or service not known`). Fixed with
  `nfs.endpoint = "10.30.0.11"` (gallium) / `"10.30.0.10"` (carbon) — the LAN IPs
  the legacy nfs-mesh used. Verify:
  ```bash
  ./verify-carbon.sh   # wg handshake + both nfs4 mounts readable
  ./verify-gallium.sh
  ```

- [x] **zwave-js starts** — RESOLVED this session, but the rename to `secrets.json`
  was only part of it; TWO more failures surfaced post-deploy (see the secret
  audit below — same class of bug):
  1. the credstore blob must be encrypted **nameless** (`--name=`, as
     `credsync write` does). It had been hand-encrypted *with* a name, so loading
     it under the renamed id `secrets.json` failed: "Name in credential doesn't
     match expectations."
  2. zwave-js-server 3.4.0 wants the keys **nested** under `securityKeys` /
     `securityKeysLongRange` (CamelCase: `S0_Legacy`, `S2_*`), not the flat
     `s0_legacy_key` snake_case form the blob held.
  ```bash
  ssh server@carbon.gio.ninja 'systemctl status zwave-js --no-pager'
  ```

- [ ] **mealie OIDC + SMTP** (ExecStart env-wrapper dropped; now relies on `*_FILE`
  env vars): log in via Pocket ID and trigger a mail-sending action.

- [ ] **prometheus `garage-metrics-token`** (receiver-only on carbon; provisioned on
  gallium and pushed):
  ```bash
  ssh server@carbon.gio.ninja 'systemctl status "secret-push-garage-metrics-token@*"; ls -l /run/credentials/prometheus.service/ 2>/dev/null'
  ```

- [ ] **Home Assistant** — confirm the **bedroom AC** package and **Matter**
  integration loaded (both were restored this pass).

- [ ] **General smoke:**
  ```bash
  ssh server@carbon.gio.ninja  systemctl --failed
  ssh server@gallium.gio.ninja systemctl --failed
  ```
  Consul: all registrations healthy. gatus: green.

## Fix-if-broken (pre-agreed fallbacks)

- Tunnel down → IP endpoint (above).
- Host won't boot the new generation → `sudo zfs rollback -r tank@<tag>` (per
  dataset, using the tag each snapshot script printed) and select the previous
  bootloader entry.

## Follow-ups — make this session's manual fixes permanent

- [ ] **Commit the config + certs.** Uncommitted work: `nfs.endpoint` on both
  hosts; re-added `ssh.hostKey` (carbon/gallium now enrolled in the SSH host CA);
  the credsync push rework — `root@` → `server@` + passwordless sudo, because
  `PermitRootLogin = "no"` fleet-wide blocked the old root push — across
  `modules/aspects/secrets/{_expand,_test}.nix` and `modules/checks/nfs.nix`; the
  two `[credsync_push_keys]` in `homelab.toml`; `gradient-disable.nix`; and the
  signed host certs under `modules/aspects/ssh/data/certs/` (from `ssh-ca sync`).
- [ ] **gradient is temporarily MASKED** on carbon via
  `modules/hosts/carbon/gradient-disable.nix` (masks gradient-server / -worker /
  -deployer; the deployed apps eater-of-feeds + yesman keep running). Delete the
  file and redeploy once garage/gallium and the gradient secrets are settled.
- [ ] **KEEP `relay-wg-nfs-keys.sh` until carbon's mesh is back.** It hand-relays
  the wg pubkeys host→host via cadmium. It is *not* obsolete: `fleet.secretsPush.
  enable` now defaults to `false`, so the credsync push no longer self-heals. If
  carbon's restored wg key doesn't survive, this script is the only way to get the
  new pubkey to gallium. Delete it after the rebuild verifies the mesh (Phase 12).
- Verify helpers left in the tree: `verify-carbon.sh` / `verify-gallium.sh`
  (read-only, run on cadmium).

## INVESTIGATE — fleet.secrets `_` ↔ `-` rename failures (systemic, not one-offs)

> **Closed by the teardown (2026-07-30).** The audit below is superseded: the
> snake_case rename makes name == credential id == blob name everywhere, and the
> three surviving rename call sites are fixed at the consumer. No nameless-blob
> dance remains. Kept for the mechanism write-up, which is still the clearest
> explanation of why the zwave bug happened.

Several secrets had to be renamed between `_` and `-` during the migration and a
bunch broke. This is a **class** of failure worth a real audit, not case-by-case
patching.

Mechanism (confirmed via the zwave bug): fleet.secrets names must be `[a-z0-9-]`
(hyphens only), but upstream modules load credential ids containing `_` or `.`
(`gradient_jwt_secret`, `secrets.json`). So the aspect emits a **rename** —
`LoadCredentialEncrypted=<module_id>:<hyphen-blob>`. A rename only works if the
blob is encrypted **nameless** (`--name=`). Any secret **hand-provisioned with
`systemd-creds encrypt --name=X`** (embedding a name) fails to load under the
renamed id with "Name in credential doesn't match expectations" — exactly the
zwave failure, and likely others.

- [ ] Audit every **manually-provisioned** fleet.secret (no generator) whose
  use-site renames (`credential.name` ≠ the secret's own name): confirm its
  credstore blob is nameless. Re-write offenders via `<value> | credsync write <name>`.
- [ ] Prime suspects: all `gradient-*` (13 secrets, underscore-mapped — currently
  masked, so the breakage is latent and will bite on re-enable), plus mealie,
  `garage-metrics-token`, and anything with an `=<x_y>:<x-y>` mapping.
- [ ] Consider a guard so this can't silently recur — e.g. a `credsync verify` /
  flake check that flags a blob whose embedded name ≠ the id it's loaded under.

### RESOLUTION (2026-07-05) — underscores only, no `-` in secret names

New rule: **agevault secret/credential names never contain `-`; use underscores
(snake_case)**. Then name == credential id == blob name everywhere, so there is no
`_`↔`-` rename and this whole failure class disappears (no nameless-blob dance, no
"name doesn't match" mismatch). See memory `feedback_secret_names_underscores`.

- Done — the new agevault `fleet.credentials` system is already underscore-only:
  `restic_password`, `restic_s3_credentials`, `step_ca_provisioner_password`,
  `gatus_push_token`, `pushover_app_token`, `pushover_user_key`. (Config renamed;
  vault side handled separately.)
- [ ] Rename to underscores as each is migrated off the old
  fleet.secrets/gio.credentials system into agevault: `caddy-cloudflare-api-token`,
  `gradient-cache-netrc`, `gradient-deployer-api-key`, `syncoid-ssh-key`,
  `netdata-pushover-app-token`, `netdata-pushover-user-token`, and any remaining
  `gradient-*` / other hyphenated ids.

## agevault — new age-based secrets system (successor to fleet.secrets)

Building the age-based secret manager from `docs/pi-ca-secrets-plan.md` →
"Secret manager". Built **additively alongside** the credsync `fleet.secrets`
aspect (not modifying it); secrets cut over one at a time.

> **Superseded in part (2026-07-30).** The additive/per-secret approach is
> replaced by "Retire the delivery half of fleet.secrets" above: agevault becomes
> the sole delivery path in one pass, and `fleet.secrets` is kept as the emission
> layer rather than being reimplemented. The "NOT built yet — consumption/emission
> layer" note below no longer describes the plan: nothing needs hand-writing,
> because the surviving half of `fleet.secrets` already emits it.

- **CLI = `agevault`** — a `writeNushellApplication` in
  `modules/packages/agevault/` (mirrors the `credsync` package: `.nu` + `.nix` +
  `_test.nix` VM test; VM test passes). Runs *inside the separate offline
  secrets repo* (out-of-band, never a flake input). Subcommands
  `cat/edit/rm/push/rekey/generate-toml`; `age` (+ age-plugin-yubikey) at rest,
  decrypt-locally → `systemd-creds encrypt --name=<name>` over ssh onto the
  host. Filename sans `.age` == credential name verbatim → no `_`↔`-` renames
  (kills that bug class). Config (`config.toml` in the secrets repo):
  `manifest_path` (abs path to the committed manifest), `identities`,
  `[destinations]`.
- **`fleet.credentials` aspect** (`modules/aspects/credentials/`, wired into
  `den.default`) — reads the names-only **TOML** manifest the CLI generates
  (`secrets.toml` at the repo root by default; path is the configurable
  `fleet.credentials.manifestFile`). Exposes read-only `fleet.credentials.
  available` (this host) + `.manifest` (whole) for den aspects + everything
  else, and **asserts at eval time** that every name in `fleet.credentials.
  needs` is in the manifest for that host (missing file OR missing secret = hard
  build error). NOTE: in the den tree credential needs are declared via
  fleet.secrets use-sites, not the (now-dead-in-den) `gio.credentials`; cut a
  secret over by moving it to a `fleet.credentials.needs` entry.
- **Eventual goal:** fold the whole thing into a unified **`fleet.credentials`**
  namespace (delivery + consumption in one). The `needs`/manifest aspect is the
  first piece of that fold.
- **NOT built yet — consumption/emission layer.** `fleet.credentials` today is
  **verification-only**: it exposes the manifest facts and asserts `needs`, but
  emits **no systemd wiring**. Unlike the old `fleet.secrets` (whose `_expand.nix`
  generates `LoadCredentialEncrypted=`, env-wrapper exports, and `.path`/`.target`
  units from use-sites), a host consuming an agevault credential must still
  **hand-write its `LoadCredentialEncrypted=`** (and any env-wrapper). Declaring
  `fleet.credentials.needs` only keeps the hand-written directive and the manifest
  in sync at eval time. Building the use-site → systemd-drop-in emission layer
  (so `LoadCredentialEncrypted=` is generated, as on the fleet.secrets side) is
  the outstanding migration before a secret is fully off manual wiring.

## Deferred — strontium secrets (migrate with the secrets work)

strontium's three creds (`restic-password`, `restic-s3-credentials`,
`step-ca-provisioner-password`) are now **in agevault** — copied into the offline
secrets repo and listed in `secrets.toml`. The host declares them via
`fleet.credentials.needs` (restic pair in `modules/hosts/strontium/default.nix`,
provisioner password in `step-ca.nix`), so a missing/renamed blob is now an
eval-time error instead of a boot failure.

- [x] Creds copied into agevault + present in `secrets.toml` for strontium.
- [x] `fleet.credentials.needs` declared for all three (eval-time verification).
- [ ] **Still manually wired.** Each `LoadCredentialEncrypted=` on strontium is
  **hand-written** (restic service, the `restic-strontium` `systemd-run` wrapper,
  and `step-ca-init`) — `fleet.credentials` doesn't emit systemd wiring yet (see
  the "NOT built yet — consumption/emission layer" note in the agevault section).
  These finish migrating only once that emission layer exists and generates the
  `LoadCredentialEncrypted=` directives, as the old fleet.secrets side does.
- Delivery is via `agevault push` (decrypt locally → `systemd-creds encrypt` onto
  the host); the blobs are host/TPM-bound and re-pushed on any reinstall. (See
  `docs/pi-ca-secrets-plan.md`.)
- **Push reports `updated` / `unchanged` per secret.** systemd-creds ciphertext
  is non-deterministic + TPM-bound, so change detection runs on the *target*: a
  content-hashed receiver cached at `/run/agevault/` (root-only; copied on first
  push, retried once) decrypts the current blob and `cmp`s it byte-for-byte
  against the incoming plaintext, re-encrypting only on a real change. Pushing an
  already-live secret prints `unchanged` — a built-in check that the agevault
  copy matches what's on the host (as confirmed re-pushing the strontium three).

## step-ca cutover cleanup (Deploy 3) — DONE IN REPO, pending deploy

Torn out **in the flake** on 2026-07-03 (ahead of the "all hosts incl carbon"
precondition — the user opted in; the four live hosts are on new certs + verified,
and carbon is a from-scratch rebuild that'll enroll fresh anyway). All toplevels +
the ssh-cert/ssh-access checks eval clean. Design: `docs/pi-ca-secrets-plan.md`;
enroll: `docs/onboarding-a-host.md`.

Done:
- [x] Dropped the old ecdsa CA from `data/host-ca.pub` + `data/user-ca.pub` (new-only).
- [x] Removed the `serveRenewedHostCert` toggle (schema option, the `mkIf` guard →
  always `mkForce` the live cert, and the `= true` in `clients.nix`).
- [x] Removed old static certs (`data/certs/*`); `host-cert.nix` is now trust-only
  (`@cert-authority` + revocations), `enrolledNames` re-sourced from the den host
  list; `access.nix` dropped the dead file-based user-cert delivery.
- [x] Retired the hand-rolled signer: deleted `modules/aspects/ssh/ca.nix`,
  `modules/packages/ssh-ca/`, `check.nix` (`ssh.data-complete`), the cadmium
  `den.aspects.ssh-ca` include, and the `check-ssh-data` prek hook.

Remaining:
- [ ] **Deploy the four live hosts** (cadmium/cesium/gallium/strontium) to land the
  teardown — low urgency; until then they harmlessly still trust both CAs and
  cadmium still runs the now-idle old signer. After deploy: `ssh <host>` still
  cert-verified (new-CA-only); `prek run -a` clean.
- [ ] **carbon**: on its rebuild, enroll fresh (its old cert is no longer trusted).
- [x] **rhodium**: SSH enabled in its host config — dropped `ssh.enable = false`,
  set `ssh.hostKey` (real ed25519 key, though see cleanup below). Enrolled via
  `ca-enroll-host rhodium` on strontium and the cert pasted on rhodium — now
  cert-verified through the host CA (done).
- [x] **rhodium DNS**: `rhodium.gio.ninja` didn't resolve because it had both an
  auto A record (static den host) and a leftover `rhodium.CNAME` in
  `modules/hosts/carbon/dns-aliases.nix` — an illegal A+CNAME collision. Dropped
  the CNAME line; deployed and verified resolving.
- [ ] Mark the cutover complete in `docs/pi-ca-secrets-plan.md`.

## New hosts — homelab.toml metadata + deploy cleanup

When a host graduates from bring-up to deployed, make sure its `homelab.toml`
`[machines.<host>]` block is complete and stop leaning on bring-up shims.

- [ ] **Every new host needs a `[machines.<host>]` block** with
  `hardwareDescription`, `physicalLocation`, and `useDescription` (plus `.deploy`
  / `.consul` sub-blocks as needed). rhodium + strontium already have theirs —
  keep this in mind for the next Pi/host so it isn't forgotten. (Onboarding
  checklist: `docs/onboarding-a-host.md` §4.)
- [ ] **rhodium `[machines.rhodium.deploy]`**: still `sshDestination =
  "server@10.30.0.12"` with a "restore once DNS serves it" TEMP note. DNS now
  resolves `rhodium.gio.ninja` — switch it back to the hostname and drop the note.

## Cleanup — drop the now-dead `ssh.hostKey`

Since the step-ca cutover, `host.ssh.hostKey` is **vestigial**: its only reader,
`hostTargetsOf` in `modules/aspects/ssh/_types.nix`, has zero consumers (host
verification is CA-name-based via `@cert-authority`; renewal reads the live key
on the host). The field is still schema-*required* for enabled hosts, so it can't
just be deleted piecemeal.

- [ ] Remove `hostTargetsOf` (dead) and drop/relax the `ssh.hostKey` schema option
  in `modules/aspects/ssh/schema.nix` (or default it to `null`).
- [ ] Delete the hardcoded `ssh.hostKey = "ssh-ed25519 …";` lines from every host
  (cadmium, gallium, carbon, cesium, strontium, rhodium) and the `= null` stubs in
  the `modules/checks/*` fixtures.
- [ ] Update `docs/onboarding-a-host.md` (step 3) to stop asking for the host key.

## OIDC / user-cert phase — retire convenience keys (later, gated on Pocket ID)

Once `step ssh login` (OIDC via Pocket ID) is the everyday path, move user access
off long-lived `authorized_keys` and onto short-lived OIDC certs — but **keep
break-glass forever**. The CA/IdP must never be a hard dependency for login (see
the tiers in `docs/pi-ca-secrets-plan.md`): remove *all* keys and one of
Pocket ID / step-ca / DNS being down locks you out of every host at once.

- [ ] **Prereq:** wire the Pocket ID OIDC provisioner into strontium's `ca.json`
  (another `rm ca.json` + regen) with a principal template mapping the OIDC
  identity → `<user>@<host>`; confirm `step ssh login` issues a working cert.
- [ ] **Split the keys in `homelab.toml`:** move the break-glass FIDO2 keys
  (`break-glass-a`/`-b`, `sk-ssh-ed25519`) out of `ssh_keys` into a dedicated
  `break_glass_keys` list.
- [ ] Wire `break_glass_keys` into every host's admin `authorized_keys`
  (giodamelio + server accounts), **always applied**, independent of `ssh_keys`.
- [ ] Once OIDC covers everyday access, empty the convenience `ssh_keys`
  (laptop/desktop/phone ed25519 keys — now replaced by OIDC certs).
- [ ] Phone (Termius): its enclave cert comes from `step ssh certificate --sign`
  of the exported pubkey (can't use `step ssh login`).
- [ ] End state: `authorized_keys` = **break-glass hardware keys only**; everyday
  = OIDC certs; serial/console = last resort.
