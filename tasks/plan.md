# Implementation Plan: Migrate carbon & gallium into den

## Overview

The two server hosts (`carbon`, the services box; `gallium`, the NAS) are the last
big things still living under Blueprint in `nix/hosts/`. The den framework's
**infrastructure + rendering** layer is already in place (ssh, fleet.secrets,
fleet.dns, host.network, fleet.nfs, consul, fleet.services → reverse-proxy /
consul / prometheus-scrape / homer, plus server aspects monitoring/gatus/
zfs-backup/deployed-apps/reverse-proxy). What is **not** migrated is everything
that actually runs *on* the two hosts: ~24 carbon service daemons, 7 gallium
service daemons, the host scaffolding, and a handful of pure-infra modules they
still import. This plan moves them across, host by host, with drv-parity as the
correctness gate.

## Architecture Decisions

- **"den wins" is atomic per host.** `flake.nix` carves
  `nixosConfigurations = bp // fp`. The instant `modules/hosts/<h>/` declares
  `den.hosts.*.<h>`, den's config *fully replaces* Blueprint's for that host —
  there is no half-migrated host in the live flake output. Therefore each host is
  built to **drv-parity** inside this worktree branch first, and the
  `nix/hosts/<h>/` directory is deleted only once parity (modulo intended diffs)
  is reached. Intermediate states must still eval/`nix flake check`, but the host
  is not deployed until its phase checkpoint passes.

- **Verification backbone = `check-drv-drift`** (the repo's own nushell package)
  comparing the den `…system.build.toplevel` against a **baseline drv captured
  from the current Blueprint config before any host change** (Task 0). Expected,
  allowlisted diffs: mTLS removal, `gio.credentials` → `fleet.secrets` store-path
  churn, and any aspect-induced option defaults. Everything else must match.

- **`fleet.services` is the single replacement for three old surfaces**:
  `services.gio.reverse-proxy.virtualHosts` (→ `endpoints`), `gio.services.*.consul`
  (→ `consul`, on by default), and homer/prometheus/gatus tiles (→ `dashboards` /
  `prometheus-endpoints` / `healthchecks`). The manual
  `services.gio.reverse-proxy.virtualHosts` escape hatch **still exists** on the
  reverse-proxy aspect for exotic vhosts (gradient static file serving, unix
  sockets, h2c, GET-only consul). Prefer `fleet.services`; fall back to the escape
  hatch only where the endpoint type can't express it.

- **`gio.credentials` is deleted, not ported.** It is subsumed by `fleet.secrets`
  use-sites: `loadCredentialEncrypted` → `type = "credential"`,
  `execStartWrapper.environment` → `type = "env-wrapper"`. Each service's
  credential block is rewritten as registry entries (`origin = <host>`,
  `use.<host>.services.<unit>`). See Open Question on the `envfiles` mode.

- **mTLS is gone fleet-wide** (no replacement). The only live site is carbon's
  read-only Consul vhost; it becomes a plain GET-only vhost guarded by network/
  firewall isolation.

- **Order: gallium first.** It is smaller (7 vs 24 services), it is a clean
  shakedown of the full per-service pattern, and it *produces* fleet resources
  carbon depends on: NFS exports (forgejo, paperless), garage S3 (gradient), and
  the immich Postgres pattern.

- **Shared PostgreSQL** stays per-host (peer-auth over `/run/postgresql`). A thin
  host-attached `postgresql` aspect provides the base server; per-service
  `ensureDatabases`/`ensureUsers`/`identMap` stay in each service's aspect via
  `lib.mkAfter`, matching today's layout.

## Dependency Graph

```
Phase 0 foundations (fleet-wide, no host cutover)
   ├── baseline drvs captured
   ├── infra aspects: send-metrics, nats, comin, netdata(parent/child), onepassword(server)
   └── decisions: fleet.secrets envfiles · static network facts · dns-server host · consul topology

gallium scaffolding (den.hosts entry, hw, zfs filesystems, user, host facts)
   ├── postgresql ──────────────► immich
   ├── syncthing (leaf, pattern shakedown)
   ├── samba (SMB export + fw isolation)
   ├── attic (fleet.secrets envfile case)
   ├── garage (S3, multi-endpoint) ──────────────────────────────► carbon: gradient
   ├── immich (shared pg + metrics proxies + prometheus)
   ├── jellyfin (5 daemons, media group, GPU)
   └── fleet.nfs exports (forgejo-repos, paperless) ─────────────► carbon: forgejo, paperless
   └── CHECKPOINT: drv parity → delete nix/hosts/gallium → deploy

carbon scaffolding (den.hosts entry, hw, disko, user, dns.serve, hammond net, consul webUi, GET-only consul vhost)
   ├── postgresql
   ├── pocket-id (OIDC provider; runtime dep of many) ──► mealie/miniflux/grist/paperless/forgejo/gradient
   ├── leaf: mealie · miniflux · loki · grafana · openbao · home-assistant · netdata · node-hp-scan-to · homer
   ├── prometheus server (scrapes whole fleet; after gallium done)
   ├── gatus status page
   ├── forgejo (needs gallium NFS + OIDC + runner)
   ├── paperless (needs gallium NFS + OIDC + gotenberg)
   ├── solidtime (PHP-FPM + app key)
   ├── grist (container + OIDC)
   ├── windmill (container workers + DB)
   ├── restate (DI for deployedApps) ──► yesman, eater-of-feeds
   ├── hooks (webhook relay) ──┐
   ├── gradient (needs forgejo + garage + restate + hooks) ◄─┘
   └── yesman · eater-of-feeds (deployedApps)
   └── CHECKPOINT: drv parity → delete nix/hosts/carbon → deploy

cleanup: delete dead Blueprint modules + docs; update AGENTS.md/CLAUDE.md
```

## Task List

### Phase 0 — Foundations (fleet-wide, no host cutover)

#### Task 0: Capture baseline drvs
**Description:** Before touching any host, record the current Blueprint `toplevel`
derivation paths for carbon and gallium so every later phase can drift-check
against a fixed baseline.
**Acceptance criteria:**
- [ ] `carbon.drv` and `gallium.drv` baseline paths saved under `tasks/baseline/`.
**Verification:**
- [ ] `nix path-info --derivation .#nixosConfigurations.{carbon,gallium}.config.system.build.toplevel` recorded.
**Dependencies:** None. **Scope:** XS. **Files:** `tasks/baseline/*`.

#### Task 1: Port pure-infra modules to den aspects
**Description:** Convert the host-agnostic Blueprint modules that both hosts import
and that have no fleet dimension: `send-metrics`, `nats`, `comin`,
`netdata` (parent for carbon, child for gallium), and confirm `onepassword` is
appropriate on servers (split a server variant if not). Mechanical conversions
mirroring the existing `monitoring`/`zfs-backup` aspects.
**Acceptance criteria:**
- [ ] `modules/aspects/.../{send-metrics,nats,comin,netdata-parent,netdata-child}.nix` exist as den aspects.
- [ ] Each gates appropriately (host-attached, inert elsewhere).
**Verification:**
- [ ] `nix flake check` green; aspects referenced from a scratch host eval cleanly.
**Dependencies:** None. **Scope:** M. **Files:** 4-5 new aspect files.

#### Task 2: Settle the cross-cutting decisions (write them down)
**Description:** Resolve and document the four decisions that block service ports:
(a) `fleet.secrets` `envfiles` strategy (attic, paperless-env); (b) carbon/gallium
static network facts (IPs/interfaces from `homelab.toml`, plus how carbon's
`hammond` NAT/DHCP-server NIC is handled — it is *not* the LAN interface);
(c) which host runs `dns.serve` (replacing `lan-dns`); (d) consul cluster topology
(`server`/`webUi`/`bootstrap_expect`).
**Acceptance criteria:**
- [ ] Each decision recorded in this plan's "Decisions" section with the chosen approach.
**Verification:**
- [ ] Human sign-off on the four answers.
**Dependencies:** None. **Scope:** S. **Files:** `tasks/plan.md`.

### Checkpoint: Foundations
- [ ] `nix flake check` green; baselines captured; decisions signed off.

### Phase 1 — gallium scaffolding

#### Task 3: gallium host scaffolding (no services)
**Description:** Create `modules/hosts/gallium/` (default.nix + hardware + ZFS
filesystems + `server` user) modeled on `modules/hosts/rhodium`. Declare
`den.hosts.x86_64-linux.gallium` with `role = "server"`, static `network`,
`consul.enable`, `nfs.enable`, `zfs_backup` datasets, firewall/nftables, hostId.
No application services yet.
**Acceptance criteria:**
- [ ] `den.hosts.*.gallium` builds a `toplevel` with base aspects only.
- [ ] ZFS root pools + boot match `nix/hosts/gallium/{filesystems,hardware}.nix`.
**Verification:**
- [ ] `nom build .#nixosConfigurations.gallium.…toplevel` succeeds.
- [ ] `check-drv-drift` vs baseline shows only the expected "services removed" delta.
**Dependencies:** 0, 1, 2. **Scope:** M. **Files:** `modules/hosts/gallium/*`.

#### Task 4: gallium postgresql aspect
**Description:** Port the shared PostgreSQL base (`nix/hosts/gallium/postgresql.nix`)
as a host-attached aspect. Establishes the peer-auth pattern reused by immich.
**Acceptance criteria:** [ ] Postgres server present; pgcli available; peer auth scaffold ready.
**Verification:** [ ] toplevel builds; drift shows only postgres add. **Deps:** 3. **Scope:** S.

#### Task 5: gallium syncthing (pattern shakedown)
**Description:** First full vertical slice: daemon + `fleet.services` endpoint
(`syncthing-gallium` → :8384) + healthcheck + consul + dashboard, and (none) secrets.
Validates the end-to-end fleet.services rendering against the old hand-written vhost+consul.
**Acceptance criteria:**
- [ ] `fleet.services.syncthing` renders the same vhost, consul registration, DNS as Blueprint.
**Verification:** [ ] drift vs baseline = zero for the syncthing surfaces. **Deps:** 3. **Scope:** S.

#### Task 6: gallium samba (SMB export + firewall isolation)
**Description:** Port Samba SMB3 share of `/tank/hard-drive-dumping-zone`, LAN-only
firewall bound to `enp5s0`, consul TCP check on `:445`.
**Acceptance criteria:** [ ] Share, firewall interface rules, consul TCP check preserved.
**Verification:** [ ] drift zero. **Deps:** 3. **Scope:** S.

#### Task 7: gallium attic (fleet.secrets `envfile` case)
**Description:** Port atticd + the `attic-envfile` secret. This is the canonical
`execStartWrapper.envfiles` (whole-file source) case — implement per the Task 2
decision and confirm the wrapper sources the env file identically.
**Acceptance criteria:** [ ] atticd starts with creds; endpoint/consul/dashboard rendered.
**Verification:** [ ] drift = only expected fleet.secrets store-path churn. **Deps:** 3, 2. **Scope:** M.

#### Task 8: gallium garage (S3, multi-endpoint, 3 secrets)
**Description:** Port garage with its 4 endpoints (`s3`, `*.s3`, `*.web`, `admin`),
three credentials (rpc/admin/metrics tokens), dedicated user, prometheus-endpoint.
Carbon's gradient + prometheus depend on this being in the fleet.
**Acceptance criteria:** [ ] all 4 vhosts + consul + metrics endpoint + secrets rendered.
**Verification:** [ ] drift = expected secret churn only. **Deps:** 3, 4-ish. **Scope:** M.

#### Task 9: gallium immich (shared pg + metrics proxies)
**Description:** Port immich (shared Postgres peer auth, `/tank/immich`), its three
`/metrics/*` reverse-proxy rewrites, and the custom Prometheus SQL exporter (:9237);
declare distinct prometheus-endpoint jobs (immich_api/microservices/stats).
**Acceptance criteria:** [ ] immich up on shared pg; metrics proxies + scrape jobs intact.
**Verification:** [ ] drift = expected only. **Deps:** 4. **Scope:** M.

#### Task 10: gallium jellyfin (media stack)
**Description:** Port jellyfin + nzbget/prowlarr/sonarr/radarr/sabnzbd, the shared
`media` group, GPU accel (`/dev/dri/renderD128`), custom sabnzbd ExecStart, and the
6 endpoints + 5 consul registrations.
**Acceptance criteria:** [ ] all 6 services, group, GPU device, endpoints/consul preserved.
**Verification:** [ ] drift = zero (no secrets here). **Deps:** 3. **Scope:** M.

#### Task 11: gallium fleet.nfs exports
**Description:** Declare the NFS shares gallium serves that carbon will mount
(forgejo-repos, paperless). Origin = gallium; consumers added when carbon's
forgejo/paperless land. Per [[fleet-nfs-and-nfs-vmtest-gotchas]].
**Acceptance criteria:** [ ] `fleet.nfs` exports present; WG mesh keys wired.
**Verification:** [ ] toplevel builds; nfs VM test (if run) passes. **Deps:** 3. **Scope:** S.

### Checkpoint: gallium complete
- [ ] `check-drv-drift` carbon-baseline-equivalent: gallium den drv == Blueprint drv modulo allowlist.
- [ ] `nix flake check` green; (optional) gallium VM smoke test.
- [ ] **Delete `nix/hosts/gallium/`**; re-run `nix flake check`.
- [ ] Deploy gallium; confirm services healthy in Consul/gatus. **Review with human.**

### Phase 2 — carbon scaffolding

#### Task 12: carbon host scaffolding (no services)
**Description:** Create `modules/hosts/carbon/` (default.nix + hardware + disko +
`server` user). `role = "server"`, static `network`, `consul.enable` +
`consul.webUi`, `dns.serve.enable` (replaces `lan-dns`), `zfs_backup` datasets,
firewall/nftables. Includes carbon's special `hammond` networking (USB-NIC DHCP
server + nftables NAT) as a host-local block per Task 2, and the GET-only consul
read-proxy vhost **without mtls**.
**Acceptance criteria:**
- [ ] carbon den `toplevel` builds with base aspects + networking only.
- [ ] consul read-only vhost is GET-only, no mtls.
**Verification:** [ ] `nom build` ok; drift vs baseline = "services removed" + mtls-gone only.
**Dependencies:** Phase 1 checkpoint, 0-2. **Scope:** L (break out hammond if needed). **Files:** `modules/hosts/carbon/*`.

#### Task 13: carbon postgresql aspect
**Description:** Shared Postgres base for carbon (forgejo, gradient, miniflux,
mealie, solidtime, windmill, …). Same peer-auth pattern as Task 4.
**Acceptance criteria:** [ ] server + pgcli + identMap scaffold. **Verification:** [ ] drift add-only. **Deps:** 12. **Scope:** S.

#### Task 14: carbon pocket-id (OIDC provider)
**Description:** Migrate Pocket ID early — it is the runtime OIDC dependency for
mealie/miniflux/grist/paperless/forgejo/gradient. Includes its OTEL Prometheus
exporter (:9464) and the `login` endpoint + caddy cloudflare token secret.
**Acceptance criteria:** [ ] login.gio.ninja up; encryption-key secret; metrics endpoint.
**Verification:** [ ] drift = expected secret churn. **Deps:** 12. **Scope:** M.

#### Tasks 15-23: carbon leaf services (one task each)
Each is a self-contained vertical slice: daemon + `fleet.services` (endpoint /
healthcheck / consul / dashboard / prometheus-endpoint) + `fleet.secrets`.
- **15 mealie** — NixOS svc; pg; OIDC; SMTP/OpenAI/OIDC secrets via env-wrapper. Scope S.
- **16 miniflux** — NixOS svc; pg; OIDC secrets. Scope S.
- **17 loki** — NixOS svc; no secrets. Scope S.
- **18 grafana** — NixOS svc; `grafana-secret-key` (note `credentialPath` reference rewrite). Scope S.
- **19 openbao** — NixOS svc; special health-check params. Scope S.
- **20 home-assistant** — NixOS svc + zwave-js (`zwavejs-secrets.json`), serial device. Scope M.
- **21 netdata (parent)** — uses Task 1 aspect + cronitor. Scope S.
- **22 node-hp-scan-to** — custom systemd; paperless group; scanner IP. Scope S.
- **23 homer** — static Caddy vhost (no daemon); the `dashboards` facet should now
  generate most tiles — reconcile generated vs hand-written config. Scope M.
**Acceptance (each):** [ ] daemon + endpoints + consul + secrets match baseline.
**Verification (each):** [ ] drift = expected churn only. **Deps:** 12 (+13 for pg svcs, +14 for OIDC).

#### Task 24: carbon prometheus server
**Description:** Port the Prometheus *server* with its large scrape set. Most
targets should now come from fleet `prometheus-endpoints` (gallium done in Phase 1);
keep the non-fleet ones (unifi-poller, consul, comin) explicit. Includes
`garage_metrics_token`/`unifi password` secrets and `host.prometheus.enable`.
**Acceptance criteria:** [ ] scrape config covers the same targets; remote-write/loki intact.
**Verification:** [ ] diff the rendered prometheus.yml against Blueprint; drift = expected. **Deps:** 12, Phase 1 done. **Scope:** L.

#### Task 25: carbon gatus status page
**Description:** Port the gatus status page (`gio.gatus` aspect already exists);
populate checks (it's not auto-wired to fleet.services).
**Acceptance criteria:** [ ] same checks/groups. **Verification:** [ ] drift zero. **Deps:** 12. **Scope:** S.

#### Task 26: carbon forgejo (+ runner)
**Description:** Port forgejo + the custom runner systemd service. Needs the gallium
NFS mount (`fleet.nfs` consumer + `mounts` on the service), OIDC auto-login rewrite,
runner registration script + token secret. Wire gallium's Task 11 export to carbon here.
**Acceptance criteria:** [ ] forgejo on NFS-backed repos; runner registers; OIDC rewrite present.
**Verification:** [ ] drift = expected; (optional) NFS VM test. **Deps:** 12, 13, 14, 11. **Scope:** L.

#### Task 27: carbon paperless
**Description:** Port paperless (pg, gotenberg, OIDC SSO redirect, NFS media mount,
`paperless-env` envfile secret). Second `envfiles` case (see Task 2).
**Acceptance criteria:** [ ] paperless + gotenberg up; NFS media; OIDC; env secret.
**Verification:** [ ] drift = expected. **Deps:** 12, 13, 14, 11. **Scope:** M.

#### Task 28: carbon solidtime
**Description:** Port the Laravel app: PHP-FPM pool + setup oneshot (migrations),
`solidtime-app-key` into both units (env-wrapper), socket-based vhost via the
reverse-proxy escape hatch, custom state dirs.
**Acceptance criteria:** [ ] setup→fpm ordering; app key in both; php_fastcgi vhost.
**Verification:** [ ] drift = expected. **Deps:** 12, 13. **Scope:** M.

#### Task 29: carbon grist (container + OIDC)
**Description:** Port the Quadlet/OCI grist container, its session/OIDC secrets, vhost.
**Acceptance criteria:** [ ] container unit + secrets + vhost preserved.
**Verification:** [ ] drift = expected. **Deps:** 12, 14. **Scope:** M.

#### Task 30: carbon windmill (container workers + DB)
**Description:** Port windmill server (pg) + the two OCI worker containers
(windmill-full), native worker group, socket DB access.
**Acceptance criteria:** [ ] server + 2 workers + DB wiring preserved.
**Verification:** [ ] drift = expected. **Deps:** 12, 13. **Scope:** M.

#### Task 31: carbon restate (deployedApps DI)
**Description:** Port restate (custom module exposing `gio.restate.deployments`),
admin/ingress endpoints, auto-provision, service-registration oneshots. Must land
before yesman/eater-of-feeds.
**Acceptance criteria:** [ ] admin+ingress vhosts; deployments facet available.
**Verification:** [ ] drift = expected. **Deps:** 12. **Scope:** L.

#### Task 32: carbon hooks (webhook relay)
**Description:** Port webhookcatcher socket+service, GitHub-App HMAC + Gradient
bearer webhook secrets, firewall :47291, socket vhost. Couples gradient↔restate.
**Acceptance criteria:** [ ] socket+service, 3 hooks, secrets, firewall preserved.
**Verification:** [ ] drift = expected. **Deps:** 12, 31. **Scope:** M.

#### Task 33: carbon gradient (hardest)
**Description:** Port gradient server+worker, 11+ credentials, Forgejo/GitHub-App/
Pocket-ID/garage-S3 integrations, the three declared projects, giopkgs override.
Depends on forgejo, garage (gallium), restate, hooks all being present.
**Acceptance criteria:** [ ] server+worker up; all integrations + projects + secrets rendered.
**Verification:** [ ] drift = expected secret churn only; build green. **Deps:** 8, 12, 14, 26, 31, 32. **Scope:** L.

#### Task 34: carbon deployedApps — yesman + eater-of-feeds
**Description:** Port the two gradient-managed deployedApps: yesman (socket, h2c
Restate SDK vhost) and eater-of-feeds (port 38291, sqlite), via `gio.deployedApps`
+ `gio.restate.deployments`.
**Acceptance criteria:** [ ] both registered with restate; vhosts/sockets preserved.
**Verification:** [ ] drift = expected. **Deps:** 31, 33. **Scope:** M.

### Checkpoint: carbon complete
- [ ] `check-drv-drift` carbon den drv == Blueprint baseline modulo allowlist.
- [ ] `nix flake check` green; (optional) carbon VM smoke test.
- [ ] **Delete `nix/hosts/carbon/`**; re-run `nix flake check`.
- [ ] Deploy carbon; confirm all services healthy in Consul/gatus/prometheus. **Review with human.**

### Phase 3 — Cleanup

#### Task 35: Remove dead Blueprint modules & docs
**Description:** Once both hosts are off them, delete the now-unused
`nix/modules/nixos/{credential,mtls,client-mtls,lan-dns,send-metrics,nats,comin,
netdata-*,reverse-proxy,consul,nfs-mesh,monitoring,zfs-backup,…}.nix` and
`homelab.nix` (whatever is fully superseded), plus `docs/mtls.md`. Update
`AGENTS.md`/`CLAUDE.md` to describe den, not Blueprint, for hosts.
**Acceptance criteria:** [ ] no dangling imports; `deadnix`/`statix` clean.
**Verification:** [ ] `nix flake check`, `treefmt --fail-on-change`, `deadnix`, `statix check` all green.
**Dependencies:** both host checkpoints. **Scope:** M.

## Risks and Mitigations

| Risk | Impact | Mitigation |
|------|--------|------------|
| "den wins" flips a host live before it's complete | High | Develop to drv-parity in this worktree; delete `nix/hosts/<h>` only at the checkpoint; never deploy mid-phase. |
| `fleet.secrets` store-path churn hides real diffs in drift | Med | Maintain an explicit allowlist of expected diffs; review remaining drift line-by-line. |
| `envfiles` whole-file source has no fleet.secrets equivalent | Med | Resolve in Task 2 before attic/paperless (decompose vars vs extend env-wrapper). |
| Shared-Postgres peer auth subtly differs under den | Med | Port postgres first (Tasks 4/13); drift-check the identMap/authentication blocks. |
| gradient's transitive web (forgejo/garage/restate/hooks) | High | Sequenced last (Task 33), after all its deps; integration-test the CI loop post-deploy. |
| hammond NAT/DHCP-server NIC doesn't fit `host.network` | Med | Keep as a host-local custom block (Task 2/12); don't force it into the static-network aspect. |
| ZFS `tank/*` mounts (currently commented in filesystems.nix) | High (boot) | Treat datasets explicitly in Task 3; verify mount ordering before services that depend on them. |

## Decisions (Task 2)

**Resolved (human sign-off):**
- **envfiles strategy → decompose into vars.** Split `attic-envfile` and
  `paperless-env` into discrete `env-wrapper` variables in the `fleet.secrets`
  registry; do not extend env-wrapper with whole-file sourcing. (Enumerate each
  key in the file when porting attic Task 7 / paperless Task 27.)
- **DNS server host → carbon + gallium (replicated).** Both enable
  `dns.serve.enable`; den merges the same fleet zone on each.
- **Consul read-only vhost → drop it.** No external read-only Consul vhost; access
  Consul via the `webUi` on the host/VPN only. (Simpler than GET-only; mtls is
  gone — see [[mtls-ditched]].)

**Still to confirm during Task 2 (lookups, not blockers):**
- **Static IPs:** read carbon/gallium interface names + addresses from
  `homelab.toml` for `host.network.interfaces` (carbon binds `eno1`, gallium
  `enp5s0`; gallium consul/samba reference `10.30.0.11`).
- **Consul topology:** `server`/`bootstrap_expect` across carbon + gallium (+
  rhodium when live); two server hosts means `bootstrap_expect = 2` unless rhodium
  joins as a server.
- **stateVersion:** keep `25.11` for both (matches Blueprint) — confirm no bump.
