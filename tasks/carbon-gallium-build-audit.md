# carbon + gallium den migration — build & diff audit

Verification of the carbon (Phase 2) + gallium den migrations before the combined
deploy. Base for all diffs/drift: the Phase-0 tip (`wqmmklumnpkk`,
`d72102ae3950097ac23609952515edb871f522d5`). All drvs compared with flake-source
state neutralized (the `check-drv-drift` STRIP: `environment.etc."nixos"`,
`nixos-revision`, optnix).

## TL;DR

- **Builds:** both toplevels build everything **except** the pre-existing neovim
  `kulala-core-node_modules` FOD (hash mismatch). That is the *sole* root failure
  on both hosts and is **not migration-caused** (shared neovim aspect; hits
  cadmium identically — see `neovim-kulala-fod-build-blocker`). A 100% toplevel is
  impossible until that hash is fixed.
- **Audit:** full line-by-line audit of both nix-diffs. Every change is
  accounted-for-expected **except one minor parity regression**: netdata loses
  `CAP_NET_ADMIN` on both hosts (root cause + fix below).
- **Drift:** vs Phase-0 tip, only **carbon + gallium** drift; cadmium / cesium /
  rhodium are byte-identical.
- **Tests:** `fastest --flake .#tests` → 54/54.
- **Evals:** carbon, gallium, cadmium, rhodium eval clean; cesium fails only on
  the kulala IFD (pre-existing, unchanged).

## Full builds (`nix build --keep-going`)

| Host | Result |
|------|--------|
| carbon | Builds all services/configs/secret units. Only failures: `kulala-core-node_modules` (hash mismatch) → `kulala-core` → `vimplugin-kulala.nvim` → `nvf-with-helpers` → home-manager → toplevel. |
| gallium | Same. Non-kulala "failures" are only the top aggregations (`system-units`, `etc`, `activate`, `nixos-system-gallium`) failing *because* the HM generation (neovim→kulala) failed. |

Root failure on both = the one kulala FOD. Nothing else fails to build.

## Audit method

Two agents read the full diffs (`/tmp/{carbon,gallium}-audit.txt`) and classified
every "set of input derivation names do not match" and "environments do not match"
block against known-expected buckets, flagging anything else. Every flagged item
was then **verified directly** by evaluating real config values (nix-diff's
`←/→` arrow markers are mangled by the rtk proxy, so the raw diff text alone was
not trustworthy for a few spots).

### Expected change buckets (all confirmed benign)

1. **gio.credentials → fleet.secrets** — `*-credential-dropin` removed; `secret-dropin-*`,
   `unit-secret-*.{path,target}`, `unit-secret-provision-*`, `unit-secret-push-*`,
   `unit-fleet-secrets-status`, `secret-envwrap-*` added. garage/gradient cred
   filenames change underscore→hyphen; paths otherwise unchanged.
2. **mtls / step-ca dropped** (carbon) — `mtls-issue-*`, `step-ca*`, `step-cli`,
   `unit-step-ca*`, `unit-mtls-issue*`, the read-only consul vhost, and step-ca's
   firewall port **8443** all removed. Intentional (mTLS retired fleet-wide).
3. **consul rename** — `etc-consul.d-services.json` → `…-fleet-services.json`;
   JSON gains `meta:{}`, `tags:[]`, `method:"GET"`. Same service set.
4. **consul cluster convergence** — `bootstrap_expect` 3→2, `retry_join` now the
   carbon+gallium pair (rhodium dropped from the expectation).
5. **ssh CA** — `+user-ca.pub`, `+nix-metadata-ssh-access`, `TrustedUserCAKeys`,
   `@cert-authority` in known_hosts, `AuthorizedPrincipalsFile`.
6. **Caddyfile re-render** — formatting / vhost ordering only; all vhosts, ports,
   and the immich `/metrics/*` + solidtime php_fastcgi + gradient handle blocks intact.
7. **basic-packages swap** — lil-scripts (git-root/jview/prettypath/whichbin/open-ports)
   off the **system** path (kept in the server user's home), `bat/eza/procs/sd/du-dust/ripgrep` added.
8. **NFS mesh den-ification** — old systemd-networkd `50-wg-nfs.{netdev,network}` +
   `wg-nfs-keygen` replaced by `wg-nfs.service` + fleet.secrets WG keys + credsync push;
   `unit-mnt-*.mount`, `unit-nfs-*.target`. gallium gains the exports (deferred at Phase-0),
   carbon gains the mounts. Deterministic `nfs-forgejo` (gid 59194) / `nfs-paperless-ngx` (45450).
9. **netdata** — gallium child + carbon parent; shared `netdata-api-key` now
   origin=carbon, used by both; postgres collector; pushover health alerts.
10. **DNS** — AAAA records added (from `ula` facts, 39 records), `.lan` CNAMEs
    (cadmium/cesium/rhodium/unifi/jetkvm), service A/AAAA, SOA/format re-render.
11. **prometheus/gatus/homer fleet-facet-driven** — prometheus scrapeConfigs
    regenerated (same 17 jobs), gatus checks (duplicates de-duped, no loss), homer
    config.yml regenerated with `admin.yml` folded into a third "Admin" group.
12. **cronitor dropped** — `cronitor-check-*`, `unit-cronitor-check-*` removed (no
    den aspect; netdata's own health alerts cover it).
13. **gradient credential mechanism** — gradient reads each secret from
    `%d/<underscore-id>`; fleet.secrets can't name underscore blobs, so each is
    mapped `LoadCredentialEncrypted=<underscore-id>:<hyphen-blob>` (last-wins over
    the module's circular LoadCredential). The module's **non-secret** `database_url`
    + `gradient-state-validated.json` LoadCredential are left intact.

### Verified flags

| Flag | Verdict |
|------|---------|
| carbon `eater-of-feeds` `LockPersonality` | `true` in den — intact (false flag from mangled arrows). |
| carbon firewall `8443` missing | Correct — it was step-ca's port (dropped with mTLS). `4000` is interface-scoped (hammond's enp0s20f0u6), also correct. |
| `database_url`, `gradient-state-validated.json`, `unit-40-iot0` | All present (iot0 VLAN restored during the audit). |
| **netdata `CAP_NET_ADMIN`** | **Real regression — see below.** |

## The one real finding: netdata loses `CAP_NET_ADMIN`

`nixos/modules/services/monitoring/netdata.nix`:

```nix
AmbientCapabilities  = lib.optional isThereAnyWireGuardTunnels "CAP_NET_ADMIN";
CapabilityBoundingSet = [ … ] ++ lib.optional isThereAnyWireGuardTunnels "CAP_NET_ADMIN";
```

- **Blueprint:** the NFS mesh used systemd-networkd WireGuard (a `netdev` of
  `Kind=wireguard`), which `isThereAnyWireGuardTunnels` detects → netdata got
  `CAP_NET_ADMIN`.
- **den:** `fleet.nfs` uses a custom `wg-nfs.service` (imperative `wg`/`ip`), which
  the heuristic does **not** see → netdata loses `CAP_NET_ADMIN` on carbon **and**
  gallium.

Verified: den gallium netdata `AmbientCapabilities = []` (Blueprint `["CAP_NET_ADMIN"]`);
`CAP_NET_ADMIN` also absent from the bounding set. Config / options / package are
otherwise identical (`netdata-2.10.3`).

**Impact:** minor — only netdata's WireGuard-interface metrics. No other effect.

**Fix options (not yet applied):**
1. den netdata aspects: force `Ambient`/`BoundingSet` to include `CAP_NET_ADMIN`
   on NFS-mesh hosts (2 files; restores parity).
2. `fleet.nfs`: grant it automatically for any host on the mesh (fleet-aspect
   change; covers future mesh hosts).
3. Accept the loss.

## Held / deferred (not done, by request)

- **Not deleted:** Blueprint `nix/hosts/{carbon,gallium}` (den overrides them via
  the flake `//` merge). See `dont-delete-blueprint-until-approved`.
- **Phase I cleanup** (dead `nix/modules/nixos/*`, `mtls`, `docs/mtls.md`) — separate approved step.
- **Full `nix flake check`** — blocked in this env by the kulala FOD + KVM-off VM
  tests; covered instead by eval + 54/54 fastest tests + drift + this audit.

## Deploy reminders (manual secrets via `credsync write` on the origin host)

- **carbon:** pocket-id key, grafana key, mealie×4, miniflux×2, zwavejs, forgejo×3,
  paperless-env, solidtime-app-key, unifi password, ~13 gradient secrets +
  deployer-api-key + 2 shared webhook secrets, netdata api-key + 2 pushover tokens.
- **grist:** 3 podman secrets (`podman secret create`, as in Blueprint).
- **gallium:** garage/attic/consul/netdata + wg-nfs keys deliver via fleet.secrets pushes.
