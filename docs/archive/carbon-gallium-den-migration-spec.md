# Spec: Migrate carbon & gallium into den

## Objective

Move the two server hosts — **carbon** (services box, ~24 services) and
**gallium** (NAS, 7 services) — from the legacy Blueprint flake organization
(`nix/hosts/`) into the **den** aspect-oriented framework (`modules/hosts/`),
without changing what the machines actually do.

den already owns the desktop/Pi hosts (cadmium, cesium, rhodium) and the entire
fleet infrastructure + rendering layer (ssh, `fleet.secrets`, `fleet.dns`,
`host.network`, `fleet.nfs`, consul, and the `fleet.services` renderers for
reverse-proxy / consul / prometheus-scrape / homer, plus the `server` aspects
monitoring/gatus/zfs-backup/deployed-apps/reverse-proxy). The two server hosts
are the last large consumers of Blueprint.

**Users:** the repository owner (single operator). **Success:** both hosts are
den-native, build to derivation-parity with their pre-migration Blueprint config
(modulo an explicit allowlist), pass `nix flake check`, deploy cleanly, and report
healthy in Consul / gatus / Prometheus. The dead Blueprint modules are then
deleted.

### User stories
- As the operator, I can run `nix flake check` and build either host's `toplevel`
  with the host defined **only** in den.
- As the operator, I can confirm a migrated host is behavior-preserving by seeing
  `check-drv-drift` report only allowlisted differences vs the captured baseline.
- As the operator, I never end up with a host that is half-migrated in the *live*
  flake output (the "den wins" carve is atomic per host).

## Tech Stack

- **Nix flakes** (nixpkgs-unstable primary, nixpkgs-25.05 stable for select pkgs)
- **den** — flake-parts module (`inputs.den.flakeModule`), aspect-oriented; owns
  `nixosConfigurations` of migrated hosts via the carve in `flake.nix`
- **Blueprint** (`numtide/blueprint`) — legacy organizer, being emptied of these hosts
- **NixOS 25.11** state version; Home-Manager; Disko; ZFS
- **Verification:** `check-drv-drift` (repo nushell pkg), `fastest` eval tests
  (`.#tests`), `runDenNixOSTest`/`denTests` VM harness
- **Tooling:** treefmt (alejandra + stylua), statix, deadnix, prek hooks, jujutsu on git

## Commands

```bash
# Validate everything
nix flake check

# Build a host toplevel (den-owned once migrated)
nom build .#nixosConfigurations.gallium.config.system.build.toplevel
nom build .#nixosConfigurations.carbon.config.system.build.toplevel

# Capture / compare derivations (correctness gate)
nix path-info --derivation .#nixosConfigurations.<host>.config.system.build.toplevel
check-drv-drift            # compare current vs baseline drv (see tasks/baseline/)

# Eval test suites (fast)
fastest --flake .#tests

# Format + lint
treefmt                    # apply
treefmt --fail-on-change   # check (used in prek)
statix check
deadnix

# Make new files visible to Nix (REQUIRED for every new file)
git add <path>

# Deploy (only on explicit approval)
./deploy.sh <hostname> <ssh_user@ip>
```

## Project Structure

```
flake.nix                      → Ownership carve: nixosConfigurations = bp // fp (den wins per host)
modules/                       → den (flake-parts, loaded via import-tree)
  den.nix                      → den base wiring + den.default bundle
  hosts/<host>/                → den host definitions (target of this migration)
    default.nix                → den.hosts.<sys>.<host> + den.aspects.<host>.nixos
    hardware.nix / disko / filesystems
  aspects/                     → cross-class features
    <class>/<name>.nix         → den.aspects.<name> (core, server, services, dns, nfs, consul, network, secrets, …)
  checks/ , lib/ , packages/ , users/
nix/                           → Blueprint (legacy)
  hosts/carbon/ , hosts/gallium/   → SOURCE of truth today; deleted at each host's checkpoint
  modules/nixos/               → legacy modules; dead ones removed in Phase 3
homelab.toml                   → machine metadata, ssh keys, static IPs, wg/credsync keys
secrets/                       → age-encrypted secrets
tasks/plan.md , tasks/todo.md  → living Plan + Tasks for this spec
tasks/baseline/                → captured pre-migration drv paths
SPEC.md                        → this document (source of truth)
```

## Code Style

Follow `CLAUDE.md`/`AGENTS.md`: alejandra formatting, `lib.pipe` for transforms,
small **why**-comments only (no what-comments, no file-header blocks),
`writeShellApplication` over raw scripts. A den service port is one host-attached
aspect that declares the daemon plus its `fleet.services` and `fleet.secrets`:

```nix
# modules/aspects/server/mealie.nix — daemon + fleet declarations, host-attached.
_: {
  den.aspects.mealie.nixos = {config, ...}: {
    services.mealie = {
      enable = true;
      settings = {/* … */};
    };

    # One declaration renders vhost + DNS + consul (+ dashboard/healthcheck).
    den.hosts.x86_64-linux.carbon.services.mealie = {
      endpoint.backend.port = 9100;          # → mealie.gio.ninja reverse-proxy + DNS
      healthcheck.target = "https://mealie.gio.ninja";
      dashboard = {category = "Services"; url = "https://mealie.gio.ninja";};
    };
  };

  # gio.credentials is GONE — secrets are fleet.secrets use-sites.
  fleet.secrets.mealie-oidc-client-secret = {
    origin = "carbon";
    use.carbon.services.mealie = {type = "env-wrapper"; env-wrapper.variable = "OIDC_CLIENT_SECRET";};
  };
}
```

**Key translations (apply uniformly):**
- `services.gio.reverse-proxy.virtualHosts.<x>` → `fleet.services.<x>.endpoint*`
  (use the manual `virtualHosts` escape hatch only for sockets / h2c / static
  file serving / GET-only cases the endpoint type can't express).
- `gio.services.<x>.consul` → `fleet.services.<x>.consul` (registration is on by default).
- `gio.credentials … loadCredentialEncrypted` → `fleet.secrets … type = "credential"`.
- `gio.credentials … execStartWrapper.environment` → `… type = "env-wrapper"`.
- `gio.credentials … execStartWrapper.envfiles` → **decompose into discrete
  `env-wrapper` variables** (no whole-file source; per decision).

## Testing Strategy

Behavior preservation is the whole game, so tests are layered:

1. **Drv-parity (primary gate).** For each task, `check-drv-drift` the den
   `toplevel` against the baseline captured in `tasks/baseline/` (Task 0). Only
   **allowlisted** diffs are acceptable: mTLS removal, `fleet.secrets` store-path
   churn, dropped read-only consul vhost. Any other diff is a regression to fix or
   explicitly justify.
2. **`nix flake check`** — green at every task boundary (never a broken eval).
3. **Eval tests** — `fastest --flake .#tests` for fleet schema/secrets/ssh logic.
4. **VM tests** — `runDenNixOSTest`/`denTests` for cross-host behavior (NFS mount,
   consul join) at host checkpoints; optional per-service.
5. **Post-deploy smoke** — Consul shows all registrations healthy; gatus green;
   Prometheus scraping all fleet `prometheus-endpoints`.

Tests/checks live under `modules/checks/` and `modules/tests.nix`; baselines under
`tasks/baseline/`.

## Boundaries

**Always:**
- `git add` every new file before any Nix command (flakes only see tracked files).
- Run `treefmt` and `nix flake check` before considering a task done.
- Capture/keep the baseline drv and drift-check each migrated surface.
- Migrate **gallium before carbon** (gallium provides NFS / garage-S3 / postgres
  patterns carbon depends on).
- Keep `tasks/plan.md` / `tasks/todo.md` updated as work lands.
- Commit style: one-line imperative, no prefixes/emojis/Co-Authored-By; set author
  + committer to the repo owner.

**Ask first:**
- Deploying to a live host (`deploy.sh`).
- Deleting a `nix/hosts/<host>/` directory (the atomic cutover).
- Changing den **core** schema/aspects (vs adding a host-attached aspect).
- Adding a new flake input or bumping `stateVersion`.
- Any change that would alter on-disk state / data layout (ZFS datasets, DB names,
  NFS/SMB share paths).

**Never:**
- Commit unencrypted secrets.
- Reintroduce mTLS / step-ca / Caddy client-auth in any form.
- Leave a host half-migrated in the **live** flake output (define it in den only
  when it's built to parity; until then it stays Blueprint-owned).
- Silently fill an ambiguous diff — surface it in the drift allowlist or fix it.

## Success Criteria

- [ ] `tasks/baseline/` holds the pre-migration `toplevel` drv for both hosts.
- [ ] `modules/hosts/{carbon,gallium}/` fully define both hosts; `nix/hosts/{carbon,gallium}/` are deleted.
- [ ] `check-drv-drift` for each host: den drv == baseline drv **modulo the allowlist**.
- [ ] `nix flake check`, `treefmt --fail-on-change`, `statix check`, `deadnix` all green.
- [ ] Both hosts deploy via `deploy.sh` and report all services healthy in Consul + gatus.
- [ ] Prometheus scrapes every fleet `prometheus-endpoint`; DNS served from carbon + gallium.
- [ ] Dead Blueprint modules + `docs/mtls.md` removed; `AGENTS.md`/`CLAUDE.md` describe den for hosts.

## Open Questions (lookups, not blockers)

- Static IPs / interface names for `host.network.interfaces` (from `homelab.toml`;
  carbon `eno1`, gallium `enp5s0`, gallium references `10.30.0.11`).
- Consul `bootstrap_expect` across carbon + gallium (+ rhodium when live).
- Confirm `stateVersion` stays `25.11` for both (no bump during migration).

## Related Artifacts

- `tasks/plan.md` — phased implementation plan (Phases 0–3, 36 tasks, dependency graph, risks).
- `tasks/todo.md` — checkbox task tracker.
