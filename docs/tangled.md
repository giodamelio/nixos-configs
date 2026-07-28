# Tangled — Knot & Spindle self-hosting

Research notes for hosting a [Tangled](https://tangled.org) **knot** (git server) and,
later, one or more **spindles** (CI/CD runners) in the homelab. Covers what each
component is, what secure mode requires, the NixOS module surface, and how it all
maps onto our den / reverse-proxy / NFS / secrets patterns.

Sources: [knot self-hosting guide](https://docs.tangled.org/knot-self-hosting-guide),
[single-page docs](https://docs.tangled.org/single-page),
[core knot.nix module](https://tangled.org/tangled.org/core/blob/master/nix/modules/knot.nix),
[core vm.nix example](https://tangled.org/tangled.org/core/blob/master/nix/vm.nix),
[pyrox.dev marvin/tangled.nix](https://tangled.org/pyrox.dev/nix/blob/c2b644c214d278af12523618de952ee2eab1af3d/hosts/marvin/services/tangled.nix),
[nix.tools write-up](https://nix.tools/articles/self-hosting-tangled-knot/).

## Architecture in one paragraph

Tangled is a decentralised git collaboration platform on top of atproto. Identity,
pull requests, issues, and stars live as records on your **PDS** (your atproto
account); the public **appview** at `tangled.org` aggregates and renders them. You
self-host the parts that hold data and do work:

- **Knot** — a lightweight, headless git server. Holds the actual repositories,
  serves git over SSH (push/pull) and HTTP (clone + a WebSocket `/events` feed the
  appview subscribes to). One knot can be single- or multi-tenant. Low CPU, grows
  with repo storage.
- **Spindle** — the CI/CD runner. Subscribes to push events via jetstream, clones
  the repo from the knot **over the network**, and executes workflows either in
  Nixery-built Docker containers or in microVMs. CPU/RAM/KVM heavy.

Knot and spindle are independent services and **can live on different hosts** — the
spindle reaches repos over HTTPS, not via a shared filesystem. You register each one
by hitting the verify button on `tangled.org/settings/knots` (resp. `/settings/spindles`),
which writes an announcement record to your PDS. The public appview stays hosted by
tangled.org; we do not self-host the appview.

## Knot

### Requirements

- A hostname (e.g. `tangled.gio.ninja`) with a valid TLS cert — satisfied by our
  Caddy + Cloudflare-DNS reverse proxy.
- Your atproto DID as the owner (`did:plc:…`, from tangled.org Settings).
- SSH reachable on the git user for push/pull.
- **No shared secret.** Post-v1.7.0 the old `KNOT_SERVER_SECRET` handshake is gone;
  `KNOT_SERVER_OWNER` (your DID) is the only required identity input. The knot needs
  **no entry in `fleet.secrets`**.
- Registration is signed through the tangled.org web UI (verify button) → writes a
  `sh.tangled.knot` record to your PDS. Nothing to pre-provision on the host.

### Secure mode (what we want)

Secure mode sandboxes every git subprocess so a malicious hook/repo can't escape:

1. **Landlock** — filesystem-path restrictions limiting each git subprocess to its own
   repo dir plus required system paths. Needs **kernel ≥ 5.19** (Landlock V2). All our
   hosts run 6.x kernels, so fine.
2. **UID isolation** — each subprocess runs as a per-repo virtual UID, and repo files
   are `chown`ed to that UID. The knot process therefore needs `CAP_CHOWN`,
   `CAP_SETUID`, `CAP_SETGID`.

The NixOS module wires this up when `server.secureMode = true`:

- Adds `AmbientCapabilities`/`CapabilityBoundingSet = [ "CAP_CHOWN" "CAP_SETUID" "CAP_SETGID" ]`
  to the `knot.service` unit.
- Runs `knot migrate-isolation --force --git-dir <scanPath> --db <dbPath>` in `preStart`.
- Runs the main process as the `git` user (not `DynamicUser`).

> ⚠️ **Secure mode wants a local filesystem for the repos.** The per-repo `chown` to
> virtual UIDs is fundamentally incompatible with how we export storage: our NFSv4
> exports use `all_squash` mapping every uid/gid to a single deterministic
> `nfs-<name>` id (see `modules/aspects/nfs/`). A squashed export cannot hold distinct
> per-repo UIDs and will reject the isolation `chown`s. **If we want secure mode, the
> repo scan path must be local disk/ZFS, not an NFS mount.** This is the single most
> important constraint for the placement decision below.

### NixOS module options

Upstream module `services.tangled.knot` (from tangled.org/core, `nix/modules/knot.nix`).
Key options:

| Option | Default | Notes |
|---|---|---|
| `enable` | `false` | |
| `package` | knot binary | from the tangled flake |
| `server.owner` | — | **required**, your DID |
| `server.hostname` | — | **required**, e.g. `tangled.gio.ninja` |
| `server.secureMode` | `false` | **set `true`** |
| `server.listenAddr` | `0.0.0.0:5555` | public HTTP (front with Caddy) |
| `server.internalListenAddr` | `127.0.0.1:5444` | internal API |
| `server.dbPath` | `${stateDir}/knotserver.db` | SQLite |
| `server.appviewEndpoint` / `appviewEndpoint` | `https://tangled.org` | public appview |
| `server.jetstreamEndpoint` | `wss://jetstream1.us-west.bsky.network/subscribe` | |
| `server.plcUrl` | `https://plc.directory` | |
| `server.dev` | `false` | leave off in prod |
| `repo.scanPath` | under `stateDir` | **repos live here — keep local for secure mode** |
| `repo.mainBranch` | `main` | |
| `gitUser` | `git` | system user the knot runs as |
| `stateDir` | `/home/${gitUser}` | |
| `openFirewall` | `true` | opens TCP 22 only |
| `environmentFile` | `null` | optional; not needed without secrets |
| `motd` / `motdFile` | `null` | |
| `knotmirrors` | `["https://mirror.tangled.network"]` | |

Creates: `systemd.services.knot` running as `git`; a system user `git` with
`useDefaultShell = true`, home `stateDir`, `createHome = true`.

### SSH integration — git-SSH on port 22222 (decided)

The module **takes over the host's sshd for the git user**. It injects into
`services.openssh` a block equivalent to:

```
Match User git
  AuthorizedKeysCommand /etc/ssh/keyfetch_wrapper
  AuthorizedKeysCommandUser nobody
  ChallengeResponseAuthentication no
  PasswordAuthentication no
```

and would open TCP **22** via `networking.firewall.allowedTCPPorts` when `openFirewall`.

**Decision:** run git-SSH on the non-standard port **22222** (five twos), *not* 22 —
matching the [pyrox.dev](https://tangled.org/pyrox.dev/nix/blob/c2b644c214d278af12523618de952ee2eab1af3d/hosts/marvin/services/tangled.nix)
approach. Rationale: only git-push needs to reach the knot from the internet (cloning is
HTTPS/443); a high port kills the constant port-22 scan noise and sidesteps ISPs that
block inbound 22. Clone-for-push URLs become `ssh://git@tangled.gio.ninja:22222/…`.
Admin SSH (port 22, our CA-based `modules/aspects/ssh` access) stays LAN/VPN-only and is
**not** forwarded at the router.

Concrete wiring on gallium:

```nix
services.tangled.knot.openFirewall = false;      # don't auto-open 22

services.openssh.ports = [ 22 22222 ];            # sshd also answers on 22222
networking.firewall.allowedTCPPorts = [ 22222 ]; # host firewall opens 22222

# Keep 22222 git-only so admin SSH isn't reachable there.
services.openssh.extraConfig = ''
  Match LocalPort 22222
    AllowUsers git
  Match all
'';
```

Notes:

- The `Match User git` block is **user-scoped**, so it coexists with our CA-based admin
  SSH — it only changes auth for the `git` user (dynamic keys fetched from the knot DB
  instead of `authorized_keys`). Human logins are unaffected.
- The host firewall (`allowedTCPPorts`) is separate from the **internet edge**. Only what
  the router forwards is actually reachable from outside — see the port-forward automation
  note below. Plan: forward **22222** (git-SSH) and **443** (clone/read) at the router;
  leave 22 unforwarded.

### Reverse proxy

Front the public `listenAddr` (5555) with our Caddy reverse proxy. Caddy proxies HTTP
**and** upgrades WebSocket automatically, so the `/events` feed works with no special
config — no manual `Upgrade`/`Connection` headers needed (unlike the nginx example in
the upstream docs).

### Security model (internet exposure)

Only **two** things face the internet; everything else is localhost-bound:

| Surface | Port | Auth |
|---|---|---|
| HTTPS read/clone + `/events` WS | 443 (Caddy → 5555) | anonymous read of public repos; TLS via Cloudflare DNS |
| git-SSH push/pull | **22222** (`git` user only) | **SSH key only** — no passwords, no challenge-response |
| internal XRPC / control API | `127.0.0.1:5444` | **not exposed** |

Defence layers:

- **Push is never anonymous.** sshd's `AuthorizedKeysCommand` (`keyfetch_wrapper`) asks
  the knot per-connection for the pubkeys registered to the atproto DIDs that are
  authorized on the target repo. Anonymous/unknown keys are rejected; password and
  challenge-response auth are disabled outright. As of knot v1.15 the member/collaborator
  lists are **knot-owned data** (`sh.tangled.knot.addMember` / `sh.tangled.repo.addCollaborator`
  records), so the knot itself is the source of truth for who can write — not the firehose.
- **The `git` user is git-ops-only.** The dynamically fetched keys carry a forced git
  command, so an SSH connection as `git` can't get an interactive shell even though the
  account has a default shell.
- **Control surface is localhost.** The internal API (5444) stays on `127.0.0.1`; only
  read (5555) and SSH (22) leave the box. Server-to-server calls use JWT inter-service
  auth.
- **Secure mode = blast-radius containment.** This is the main reason to run it on an
  internet-facing box. Git servers have a history of RCE via malicious hooks and pack
  parsing; Landlock + per-repo UID isolation sandbox each git subprocess to its own
  repo, so a compromise *during a git operation* can't read other repos or escape to the
  host. It does **not** protect against bugs in the knot process itself.
- **Optional extra:** since DNS already runs through Cloudflare, the HTTPS vhost can be
  proxied (orange-cloud) to keep 443 off the direct-hit path. SSH/22 must stay direct
  (Cloudflare doesn't proxy git-SSH).

Two things the upstream docs leave vague — confirm before trusting them:

- Whether HTTP **read** of *private* repos is actually enforced. Until verified, assume
  every repo on the knot is world-readable over HTTPS.
- How a spindle authenticates to clone *private* repos (see spindle section). Public
  repos clone anonymously and sidestep the question.

## Spindle

### What it needs

- Its own hostname + DID owner (same pattern as the knot).
- An execution engine:
  - **Nixery engine** — runs steps in Docker/Podman containers from Nixery-built images.
    State persists across steps in `/tangled/workspace`. Needs Docker or Podman.
  - **MicroVM engine** — runs each workflow in a lightweight VM (NixOS/Alpine). Needs
    `/dev/kvm`, `qemu-system-*`, `mkfs.ext4`, `slirp4netns`, `/dev/vhost-vsock`,
    `/dev/net/tun`. Stronger isolation, heavier.
- CPU + RAM proportional to the workloads; optional resource caps
  (`MAX_TOTAL_MEMORY_MIB`, `MAX_TOTAL_VCPUS`, `MAX_TOTAL_DISK_MIB`).

### NixOS module options (`services.tangled.spindle`)

From the core `vm.nix` example:

```nix
services.tangled.spindle = {
  enable = true;
  server = {
    owner = "did:plc:…";
    hostname = "spindle.gio.ninja";
    listenAddr = "0.0.0.0:6555";
    queueSize = 100;
    maxJobCount = 2;
    secrets.provider = "sqlite";   # per-repo CI secrets store
  };
  pipelines = {
    workflowTimeout = "10m";
    microvm.enableKVM = true;      # microVM engine
    nixCache = {                   # optional: point at our attic
      readUrls = [ "…" ];
      uploadUrl = "…";
      trustedPublicKeys = [ "…" ];
    };
    logBucket = "";                # optional S3 for logs
  };
};
```

Other env-level knobs: `SPINDLE_SERVER_LOG_DIR` (default `/var/log/spindle`),
`SPINDLE_PIPELINES_NIXERY` (default `nixery.tangled.sh`), microVM image dirs.

### Scheduling caveat (relevant to the cadmium idea)

The spindle is **event-driven**: it runs when a push/PR event arrives via jetstream,
not on a cron. There is no built-in "only work overnight" mode. To restrict a
cadmium spindle to overnight heavy jobs you'd have to either (a) gate the unit with a
systemd timer / `Condition...` so it only accepts jobs in a window, or (b) drive the
heavy work from scheduled workflow triggers rather than push triggers, or (c) accept
that it runs whenever a matching push happens. Worth confirming the desired trigger
model before wiring cadmium in.

## Privacy, private repos, and why we're NOT replacing Forgejo

The original temptation was to replace Forgejo with Tangled because Spindles + the
NixOS CI driver are genuinely nicer. Don't — at least not now. The reasoning:

**Tangled has no private repos, and self-hosting can't fix that.** The privacy gap is
**protocol-level, not deployment-level**. atproto has no private-record primitive: the
firehose broadcasts every record, and appviews are built to consume that public stream.
So repo/issue/PR/star **metadata is public by design** regardless of who hosts the
appview. Standing up the *entire* stack (own appview + Bobbin + PDS + knot + spindle)
does **not** buy privacy — the only way to hide records is a PDS that never connects to
a relay plus a private appview pointed only at it, i.e. a non-federated island that
throws away the whole reason Tangled exists. Net: full self-hosting = a lot of work for
~zero privacy gain. (Future maybe: MLS-encrypted private sharing has been floated but is
not shipped.)

**Spindles force the repos public.** Spindles only run on Tangled **knot** repos — they
subscribe to knot push events via jetstream and cannot run CI on a Forgejo repo. So
"I want Spindles on this repo" ⇒ "this repo lives on a knot" ⇒ "this repo is public."
There is no path to Spindle CI on private code today, from any deployment.

**Therefore: coexist, don't replace.**

| Need | Home |
|---|---|
| Public repos where we want the slick Nix CI | Tangled knot (gallium) + Spindle (carbon) |
| Anything private | **Forgejo** — already self-hosted with SSO + its own Actions runner (`forgejo-runner-build`) |

Running both is conflict-free (different hosts, ports, services; they don't interact).

**Adoption path:** stand up the knot + one Spindle and move **one or two public repos**
onto it to evaluate the Spindle / NixOS-driver experience — a low-commitment test of the
actual draw, with Forgejo untouched. Reconsider a full Forgejo → Tangled replacement
**only if/when Tangled ships private repos**. That feature landing is the trigger to
watch; until then private code has no home on Tangled no matter how much we self-host.

## Homelab integration cheatsheet

Everything below mirrors existing services (see `modules/hosts/carbon/forgejo.nix`,
`modules/hosts/carbon/nfs.nix`, `modules/aspects/server/reverse-proxy.nix`).

- **DNS**: add the subdomain to the host's CNAME list in `homelab.toml` under
  `[dns."gio.ninja".cname]` → `"<host>.lan."`.
- **Reverse proxy + Consul + healthcheck**: declare a service endpoint:

  ```nix
  den.hosts.x86_64-linux.<host>.services.tangled = {
    endpoint = {
      domain = "tangled";
      backend.host = "localhost";
      backend.port = 5555;
    };
    healthcheck.target = "https://tangled.gio.ninja/";
    # mounts = ["tangled"];  # ONLY if repos are on NFS (see secure-mode warning)
  };
  ```

- **Secrets**: none required for the knot. A spindle's per-repo CI secrets are stored
  in its own sqlite provider, not `fleet.secrets`.
- **Storage on NFS (if ever needed)**: `fleet.nfs.mounts.<name>.gallium."/tank/<name>".<host>."/mnt/<name>" = {}`
  then `users.users.<svc>.extraGroups = ["nfs-<name>"]` and `mounts = ["<name>"]`.
  **But note the secure-mode incompatibility with NFS above.**

## Placement decision

### Knot — recommendation: host on **gallium**, repos on local `/tank/tangled`

Reasoning:

1. **Secure mode needs local storage.** The per-repo `chown`/UID isolation cannot work
   over our `all_squash` NFS exports. Gallium is the only host where the storage is
   *local* (ZFS `tank`), so the knot's repos and secure mode both get what they need
   with zero NFS involvement.
2. **The knot is lightweight.** It's a headless git server with low CPU needs — well
   within gallium's envelope even though gallium is the weaker (NAS) CPU. Git serving
   is I/O-bound and gallium is where the disks are.
3. **Data already lives where it belongs.** Repos on `/tank/tangled` inherit our
   existing ZFS snapshot/backup regime — no new backup path to design.
4. **No availability coupling and no waiting.** Gallium is healthy and up now. Carbon
   is currently degraded (failing disk, mid-rebuild). Hosting the knot on carbon would
   (a) make us wait for carbon and (b) couple the git server's uptime to the
   carbon↔gallium WireGuard/NFS mesh.

The "carbon + NFS dance" option is the weaker choice specifically **because** we want
secure mode: it forces repos onto a squashed NFS mount that fights the isolation model,
adds a runtime storage dependency, and buys us nothing (the knot doesn't need carbon's
CPU). If we did *not* want secure mode the NFS route would be viable, but that's not the
goal.

Trade-off to accept: gallium's sshd gains a user-scoped `Match User git` block. That's
benign (doesn't touch admin logins) but it does mean git pushes land on the NAS.

### Spindle(s) — carbon (primary), cadmium (optional, gated)

- **carbon** is the right home for the primary spindle once it's back: it has the CPU,
  it's our designated "services / CI" host, and it can run the microVM engine
  (`/dev/kvm`) or the Podman/Nixery engine. The spindle clones from the gallium knot
  **over HTTPS**, so there is *no* NFS requirement between spindle and knot — they stay
  cleanly decoupled. Point its nix cache at our attic to speed builds.
- **cadmium** as a secondary spindle is feasible but note the scheduling caveat above —
  the spindle reacts to push events, not a nightly cron, so "only overnight" needs an
  explicit gate (systemd timer / condition) or scheduled-trigger workflows. Decide the
  trigger model before adding it.

### Suggested rollout order

1. Deploy the **knot on gallium** in secure mode now (repos local on `/tank/tangled`),
   register via `tangled.org/settings/knots`, push a test repo.
2. When carbon is healthy, add the **spindle on carbon**, attach it to a repo, confirm
   it clones from the gallium knot over HTTPS and runs a pipeline.
3. Only then evaluate a **gated cadmium spindle** for heavier overnight jobs, once the
   trigger-model question is settled.

## Declarative router port-forwards via the UniFi API (to investigate)

The edge port-forwards (22222 → gallium git-SSH, 443 → reverse proxy) currently have to
be punched in by hand in the UniFi controller. Since we're a NixOS-declarative shop, it'd
be nice to manage them **during `nixos-rebuild`** so a service's required forward lands
declaratively alongside its config instead of as a manual side-step.

Research direction:

- The UniFi controller exposes an API for port-forward rules (`/proxy/network/api/s/<site>/rest/portforward`
  on modern UDM/Network-application controllers, or the older `/api/s/<site>/rest/portforward`).
  A rule is a JSON object (`name`, `fwd` = internal IP, `dst_port`, `fwd_port`, `proto`,
  `src`, `enabled`). Auth is a controller login/cookie (or an API key on newer firmware).
- Options to evaluate, roughly in order of preference:
  1. **Terraform `unifi` provider** (paultyng/unifi) driven from Nix — declarative and
     idempotent, but pulls Terraform into the loop and runs out-of-band from rebuild.
  2. **A NixOS activation/systemd-oneshot reconciler** — a small script (nushell, per our
     tooling pref) that reads a declared list of forwards from the host config and
     PUTs/DELETEs them against the UniFi REST API on each activation. Fully inside the
     rebuild, but we own the idempotency + drift logic.
  3. Check whether an existing Nix module / flake already wraps the UniFi API for this.
- Secrets: the controller credential / API key would live in `agevault` (or `fleet.secrets`
  for now) and be loaded as a credential for the reconciler unit.
- Ideal end-state: a `fleet`/`den`-level `portForwards` facet where a service declares
  `{ external = 22222; to = "gallium"; internal = 22222; proto = "tcp"; }` and the
  reconciler makes the controller match — the same pattern as our reverse-proxy/DNS facets.
- Caveats to check: controller API stability across firmware versions, whether a
  non-admin API user can be scoped to just port-forwarding, and behaviour if the
  controller is unreachable during a rebuild (must not fail the activation hard).

This is a **separate follow-up**, not a blocker for the knot rollout — do the first
forward by hand, then build the reconciler and adopt it.

## Open items to confirm before implementing

- Is the `tangled` flake input the way we'll get the `services.tangled.knot` module, or
  do we vendor the module? (Need to add the input at the end of the inputs block.)
- Exact `repo.scanPath` under `/tank/tangled` and matching ZFS dataset creation.
- Trigger model for a cadmium spindle (event-driven vs gated/overnight).
- Router forwards to punch in (manually for now): **22222** → gallium git-SSH, **443** →
  reverse proxy. Later: automate via the UniFi API (see section above).
