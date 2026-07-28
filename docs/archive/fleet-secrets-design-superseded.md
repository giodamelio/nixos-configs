# fleet.secrets — Fleet-Wide Secret Flows (design spec)

A secret is **one top-level named entry** describing its whole lifecycle:
the host it originates on, how it's provisioned there (generated, or pasted
in by hand), and which consumers on which hosts use it. The system turns each
entry into systemd units on every involved host — provision oneshots,
[credsync](./credsync.md) push units, path-activated targets, and consumer
drop-ins — so the flow "generate on A, deliver to B, start the service on B
the moment it arrives" needs zero manual steps.

Status: **interface spec, not yet implemented.** Built from scratch for den
hosts only (no Blueprint shim); the old `gio.credentials` module stays
untouched until carbon/gallium migrate.

## The interface

`fleet.secrets.<name>` is a fact on the **den fleet entity** (modules/fleet.nix
— pure data, host-agnostic: a secret is a property of the fleet, not of one
machine). The option types are registered via `den.schema.fleet.imports =
[{ options.secrets = …; }]` (the convention the ssh feature established with
`fleet.ssh.*`), and values are set at `fleet.secrets.<name>` from any module
file, usually next to the aspects of the services involved:

```nix
fleet.secrets.forgejo-runner-token = {
  origin = "carbon";                   # host where it comes into being
  generator = "openssl rand -hex 32";  # stdout = the secret, runs once

  # use.<host>.<kind>.<site> — v1 kind: services
  use.carbon.services.forgejo = {};
  use.gallium.services.gitea-runner-default = {};
};
```

### Schema

```nix
fleet.secrets.<name> = {
  # Master switch: false = the secret contributes no units on any host,
  # as if the entry didn't exist. (Blobs already on disk are not removed.)
  enable = true;

  # Host where the secret is created. REQUIRED — even manual secrets have
  # exactly one home (it's where you paste them; distribution flows from
  # there). Must be a den host name (validated at eval time, names only).
  origin = "<hostname>";

  # How the secret is produced on the origin. null (the default) = manual:
  # provision once with `<paste> | credsync write <name>` on the origin.
  # Until then, the provision unit FAILS LOUDLY with those instructions
  # (see Semantics — nothing is silently skipped).
  generator = {
    # false = don't generate: the secret behaves as manual (the provision
    # unit fails with paste instructions) while keeping the generator config
    # around — e.g. to pin a value by hand without deleting the definition.
    enable = true;

    # What produces the secret — stdout becomes the value. One of:
    #   shell text   — inline script, wrapped with `path` as its runtime PATH
    #   a path       — executable run directly (e.g. ./gen-token.sh)
    #   a derivation — runs its meta.mainProgram (lib.getExe)
    script = <shell text> | <path> | <derivation>;
    path = pkgs: [ ... ];         # runtime PATH for inline scripts only
    after = [ "<unit>" ... ];     # ordering, e.g. a service whose CLI mints it

    # Other fleet.secrets this generator derives from. Each is loaded into
    # the provision unit ($CREDENTIALS_DIRECTORY/<name>) and ordered
    # After=/Requires= its target. This is how keypairs work: store the
    # private key as one secret, derive the public as another —
    # `wg pubkey < $CREDENTIALS_DIRECTORY/<private>`. Needed secrets must
    # share this secret's origin (private keys are never shipped around
    # just to derive from them).
    needs = [ "<secret name>" ... ];
  };
  # Shorthand: any of the three script forms coerces to { script = ...; },
  # e.g. generator = "openssl rand -hex 32"

  # Extra hosts that receive the secret without a consumer (offline/manual
  # use). Hosts appearing in `use` are NEVER listed here — the copy set is
  # derived (see Semantics).
  copyTo = [ "<hostname>" ... ];

  # Consumption sites: use.<host>.<kind>.<site>. The kind level keeps the
  # format open to non-systemd consumers later (see Extensibility); v1
  # implements exactly one kind, `services`. The site key is a LABEL, not
  # necessarily the unit name — `unit` defaults to it but can be overridden,
  # so one secret can be loaded into the same unit several times under
  # different credential names.
  use.<hostname> = {
    # false = this host consumes nothing and (unless listed in copyTo)
    # drops out of the derived copy set — the origin stops pushing to it.
    enable = true;

    services = { ... };         # sites, see below
  };

  use.<hostname>.services.<site> = {
    # false = no drop-in for this site; the unit neither loads the
    # credential nor waits on the secret's target.
    enable = true;

    # Which systemd unit to attach to (without ".service").
    unit = <site>;                # default: the attr name

    # How the unit consumes the secret. Discriminated by `type`; each type
    # has its own option group. Both ship in v1.
    type = "credential";          # enum: "credential" | "env-wrapper"

    # type = "credential" — a LoadCredentialEncrypted= / LoadCredential=
    # drop-in (also the base behavior of "env-wrapper": load first, then
    # wrap). The defaults emit the bare directive
    # `LoadCredentialEncrypted=<secret name>` — no path, so systemd finds the
    # blob by name in its default credstore search path
    # (/{etc,run,usr/lib}/credstore.encrypted), the form this repo uses
    # almost everywhere.
    credential = {
      # Credential ID inside the unit (the directive's ID part): the value
      # appears at $CREDENTIALS_DIRECTORY/<name>. Override when a service
      # expects a specific credential name, or to load one secret twice.
      name = <secret name>;       # default

      # Where systemd reads the credential from (the directive's PATH part):
      #   null (default) — search the credstores for the secret's blob by
      #     name. When `name` is overridden this still finds the secret:
      #     it emits `<name>:<secret name>`.
      #   relative string — a different blob name, searched in the credstores
      #   absolute path — a regular file, or an AF_UNIX socket to connect to
      source = null;

      # true (default) → LoadCredentialEncrypted= (our blobs are always
      # systemd-creds encrypted). false → plain LoadCredential=, for odd
      # sources like sockets or pre-decrypted files — requires `source`.
      encrypted = true;
    };

    # type = "env-wrapper" — an ExecStart wrapper exports the value as an
    # environment variable (the credential load above still happens; the
    # wrapper reads from $CREDENTIALS_DIRECTORY). See "The env wrapper"
    # below for merge/collision semantics.
    env-wrapper = {
      variable = "<VAR>";       # default: secret name screaming-snaked —
                                # "forgejo-runner-token" → FORGEJO_RUNNER_TOKEN
                                # (uppercase, non-alphanumerics → "_")
    };

    # Opt-in: try-restart this unit when a new value is delivered.
    restartOnChange = false;

    # Opt-in: the secret's target Upholds= this unit — systemd continuously
    # re-starts it whenever it's down while the secret is present. Default
    # is plain Wants= (started once on first delivery), which doesn't fight
    # `systemctl stop` during maintenance. Turn on for services that must
    # ALWAYS run when their secret exists.
    upholds = false;
  };
};
```

### Host-side read-only view

On every host the base aspect mirrors that host's slice of the registry into
a **read-only** NixOS option of the same name, so service config can render
credential paths without spelling them out (the agenix `.path` pattern):

```nix
# inside any NixOS module/aspect on a host that uses the secret:
config.fleet.secrets.<name>.path           # the use-site's runtime path:
                                           # /run/credentials/<unit>.service/<credential.name>
config.fleet.secrets.<name>.paths.<site>   # per-site, when one host has several
```

`.path` is the ergonomic accessor for the common case of one use-site on the
host; with multiple sites it's an eval error naming the candidates — use
`.paths.<site>`. Computed purely from registry data (unit + credential name),
so it can never recurse into `systemd.services`. Being read-only doubles as a
guardrail: trying to *define* `fleet.secrets` inside a NixOS config (instead
of at flake level) errors immediately.

```nix
services.grafana.settings.security.admin_password =
  "$__file{${config.fleet.secrets.grafana-admin-password.path}}";
```

### More shapes

```nix
# Manual secret — no generator; paste it once on the origin, pushed from there.
# Until pasted, secret-provision-cloudflare-api-token.service on carbon fails
# visibly with the provisioning command.
fleet.secrets.cloudflare-api-token = {
  origin = "carbon";   # provision: wl-paste | credsync write cloudflare-api-token
  use.rhodium.services.acme-gio-ninja = {};
};

# Several consumers on the same host
fleet.secrets.nats-system-password = {
  origin = "gallium";
  generator = "openssl rand -hex 32";
  use.gallium.services = {
    nats = {};
    nats-exporter = {restartOnChange = true;};
  };
};

# Same secret loaded into one unit twice under different credential names
# (site keys are labels; `unit` targets the real unit)
fleet.secrets.shared-ca-key.use.carbon.services = {
  step-ca-sign = {
    unit = "step-ca";
    credential.name = "sign-key";
  };
  step-ca-rotate = {
    unit = "step-ca";
    credential.name = "rotate-key";
  };
};

# Generator that needs tools / must run after a service
fleet.secrets.forgejo-runner-token.generator = {
  script = "forgejo-cli actions generate-runner-token";
  path = pkgs: [pkgs.forgejo];
  after = ["forgejo.service"];
};

# Generator as a derivation (runs its meta.mainProgram) — e.g. a repo package
fleet.secrets.wg-mesh-key.generator = perSystem.self.wg-keygen;

# Generator as a path to an executable
fleet.secrets.grist-session-secret.generator = ./generators/session-secret.sh;

# Copied somewhere with no consumer (e.g. recovery material)
fleet.secrets.restic-password = {
  origin = "cadmium";
  generator = "openssl rand -hex 32";
  copyTo = ["gallium"];
};

# Keypair via generator.needs — public is a pure function of private, so it
# is just another (chained) secret; both flow through the normal pipeline.
fleet.secrets.wg-mesh-private = {
  origin = "cadmium";
  generator = {
    script = "wg genkey";
    path = pkgs: [pkgs.wireguard-tools];
  };
  use.cadmium.services.systemd-networkd = {};
};
fleet.secrets.wg-mesh-public = {
  origin = "cadmium";
  generator = {
    script = ''wg pubkey <"$CREDENTIALS_DIRECTORY/wg-mesh-private"'';
    path = pkgs: [pkgs.wireguard-tools];
    needs = ["wg-mesh-private"];
  };
  use.gallium.services.some-peer-consumer = {};
};

# Same pattern with age: the identity stays on the host that decrypts;
# the derived recipient (public) key flows to the hosts that encrypt.
fleet.secrets.backup-age-identity = {
  origin = "gallium";
  generator = {
    script = "age-keygen";    # full output is a valid identity file
    path = pkgs: [pkgs.age];
  };
  use.gallium.services.backup-restore = {};
};
fleet.secrets.backup-age-recipient = {
  origin = "gallium";
  generator = {
    script = ''age-keygen -y "$CREDENTIALS_DIRECTORY/backup-age-identity"'';
    path = pkgs: [pkgs.age];
    needs = ["backup-age-identity"];
  };
  use.cadmium.services.backup-encrypt = {};
  use.cesium.services.backup-encrypt = {};
};
```

Per-host-distinct values (e.g. per-machine auth keys) are separate secrets
with the host in the name and `origin` set to that host — they *are*
different secrets, so they get different entries.

## Full example

Every knob in one entry:

```nix
fleet.secrets.attic-server-token = {
  enable = true;                            # default; false = entry contributes nothing

  origin = "gallium";
  generator = {
    script = "openssl rand -hex 64";        # also accepts a path or derivation
    path = pkgs: [pkgs.openssl];            # PATH for inline scripts
    after = ["atticd.service"];             # wait for the service that can mint it
  };
  copyTo = ["rhodium"];                     # receives the blob, no consumer

  # Origin-local consumer, all defaults:
  # drop-in on atticd.service → LoadCredentialEncrypted=attic-server-token,
  # value at $CREDENTIALS_DIRECTORY/attic-server-token
  use.gallium.services.atticd = {};

  use.cadmium.services = {
    # Renamed credential id; source stays derived:
    # LoadCredentialEncrypted=server-token:attic-server-token
    attic-watch-store = {
      credential.name = "server-token";
      restartOnChange = true;               # try-restarted when a push changes the value
    };

    # Same secret, same unit, second load under another id (site key is a
    # label; unit overrides it): LoadCredentialEncrypted=upload-token:attic-server-token
    attic-watch-store-upload = {
      unit = "attic-watch-store";
      credential.name = "upload-token";
    };

    # Exports ATTIC_SERVER_TOKEN via the ExecStart wrapper; the
    # credential load still happens underneath.
    attic-uploader.type = "env-wrapper";
  };

  use.cesium = {
    enable = false;                         # travel machine: opt the whole host out;
    services.attic-watch-store = {};        # it also drops out of the copy set
  };
};
```

This one entry expands to:

- **gallium** (origin): `secret-provision-attic-server-token.service` (runs
  the generator once, after atticd), `secret-push-attic-server-token@cadmium`
  and `@rhodium` service+timer pairs (cesium excluded — disabled), and the
  holder wiring + an atticd drop-in.
- **cadmium**: holder wiring (`secret-attic-server-token.path`/`.target`) and
  one drop-in on `attic-watch-store.service` carrying both
  `LoadCredentialEncrypted=` lines; the push from gallium lists
  `attic-watch-store.service` as a restart unit.
- **rhodium**: holder wiring only — blob lands in the credstore, nothing
  consumes it.
- **cesium**: nothing.

## Semantics

- **Copy set is derived**: hosts receiving the secret = enabled `use` hosts
  (minus `origin`) ∪ `copyTo`. Declaring a use *is* declaring the copy —
  it is impossible to use a secret on a host it was never delivered to.
- **`enable` cascades**: secret-level `enable = false` silences the entry
  everywhere; host-level disables that host's consumption *and* its derived
  copy (push units disappear on the origin); site-level just drops that one
  drop-in; generator-level turns a generated secret into a manual one
  without deleting the generator config. All default `true`; disabling never
  removes blobs already on disk.
- **Provisioning is loud, never silent**: the origin always runs
  `secret-provision-<name>.service`, gated on `ConditionPathExists=!` the
  credstore blob. With a generator it creates the secret (once — values are
  stable across reboots and rebuilds). Without one, it prints the exact
  `credsync write` command to run and **exits 1** — a failed oneshot stays
  failed, shows in `systemctl --failed`, and gets re-triggered by the push
  timers, so an unprovisioned secret keeps resurfacing in monitoring until
  pasted. The moment the blob lands, the path unit fires and pushes flow —
  no rebuild needed. (A `Condition` for the missing case would *skip*
  silently — that's why it's a failing script instead.)
- **Closed by construction**: the whole flow lives in one declaration, so
  dangling consumption can't exist. Hostnames are validated against den host
  entity names; a typo is an eval error, not a silently missing credential.
- **Every type loads the credential**, value at
  `$CREDENTIALS_DIRECTORY/<credential.name>`. The directive emission rule
  (D = `LoadCredentialEncrypted` when `credential.encrypted`, else
  `LoadCredential`):

  | Settings | Emitted directive |
  |----------|-------------------|
  | all defaults | `D=<secret name>` (bare — credstore search) |
  | `name` overridden, `source = null` | `D=<name>:<secret name>` (rename still finds the blob) |
  | `source` set | `D=<name>:<source>` |

  The `env-wrapper` type does the same load first, then layers the wrapper
  on top — strictly additive, never a replacement.
- **The env wrapper** (fully defined; `env-wrapper` sites only, one wrapper
  per unit):
  - Generated for a unit only when ≥1 of its use-sites (across ALL secrets)
    has type `env-wrapper`; the drop-in resets `ExecStart=` and re-points it
    at a script that exports each variable from `$CREDENTIALS_DIRECTORY` and
    `exec`s the original command — `exec` preserves the unit's
    `Type=`/notify/pid semantics, and values exist only in process memory.
  - Requires the unit to have exactly one original `ExecStart` (read from
    `config.systemd.services.<unit>` like the old gio.credentials — proven
    recursion-safe); anything else (none, list-form, template magic) is an
    eval error naming the unit, not a silent half-wrap. Units with only
    `credential` sites never hit this constraint.
  - Exports are sorted by variable name; two `env-wrapper` sites on one unit
    exporting the SAME variable is an eval error. The wrapper exports after
    systemd's own environment setup, so they win over `Environment=`/
    `EnvironmentFile=` values from the service's own config.
  - Values are read with command substitution — trailing newlines are
    stripped (same caveat as credsync; fine for tokens, wrong for binary).
- **Change propagation**: credsync's receiver-side comparison means pushes
  are no-ops for unchanged values. On a real change the receiver activates
  the secret's target and `try-restart`s exactly the units that opted in via
  `restartOnChange` — the origin passes them as `credsync push` restart-unit
  args, computed from the registry (the origin knows every host's uses).
  Rotation = delete the blob and re-trigger provision (a future
  `secretctl rotate` can wrap this).

## Per-host expansion

The cross-cutting piece is one base aspect in `den.default.includes`,
written parametrically against den's context args:
`den.aspects.fleet-secrets = {fleet, host, ...}: …` — the fleet entity
carries the registry (`fleet.secrets`), the host context names the slice.
No file-scope `config` reach-around needed; this is the composition path the
fleet entity exists for (scope tree: flake → fleet → flake-system → host →
user). On each host it filters the registry down to that host's slice and
emits:

**Origin host:**

| Unit | Purpose |
|------|---------|
| `secret-provision-<name>.service` | oneshot, `ConditionPathExists=!` the blob; runs `generator.script` and encrypts stdout into `/usr/lib/credstore.encrypted/<name>` — or, with no generator, fails with paste instructions; `wantedBy multi-user.target`; `after` from generator |
| `secret-push-<name>@<host>.service` | oneshot per destination: `credsync push <name> root@<fqdn> [restart-units…]`; `Requires=`/`After=` provision + `network-online.target` |
| `secret-push-<name>@<host>.timer` | boot + periodic resync; retries while the destination is down, delivers rotations eventually, re-surfaces failed provisioning |

**Every host holding the secret (users, receive-only hosts, and the origin
itself when it has local uses):**

| Unit | Purpose |
|------|---------|
| `secret-<name>.path` | watches the credstore blob, activates the target on first delivery |
| `secret-<name>.target` | "this secret is present"; `Wants=` consuming units (`Upholds=` for sites that opted in) |
| drop-in per use site | the credential directive (see emission rule below), `Requires=`/`After=secret-<name>.target` on the site's `unit` |

Net behavior: a consuming service **cannot start before** its secret exists
and **starts automatically the moment** it first arrives. `Wants=` starts it
once on delivery and otherwise leaves it alone — `systemctl stop` for
maintenance is respected; a site with `upholds = true` is instead
continuously re-started whenever the secret is present. Restarts on rotation
only happen for sites that opted in via `restartOnChange`.

**Every involved host additionally runs the login warning:**

| Unit | Purpose |
|------|---------|
| `fleet-secrets-status.service` | oneshot; checks every blob this host expects against the credstore and renders warnings into `/run/issue.d/fleet-secrets.issue` (hardware terminal) and the motd path (ssh), or removes them when all present |

It runs at boot and is re-triggered by every `secret-<name>.target`
activation, so the warning clears itself the moment the last missing secret
lands. Message wording distinguishes the two cases:

- on the origin, a missing manual secret is **actionable here**:
  `secret 'cloudflare-dns-token' not provisioned — run: <paste> | credsync write cloudflare-dns-token`
- on a holder, a missing secret is **in transit**:
  `waiting for 'forgejo-runner-token' from carbon`

All consumer-side modification happens through `systemd.packages` drop-in
derivations (the `gio.credentials` trick), never by touching
`systemd.services.<unit>` directly — that's what avoids infinite recursion
once the `env-wrapper` type needs to read/wrap a unit's own `ExecStart`.

## Extensibility (deliberate, not yet built)

The data format is shaped so these arrive as *additions*, never reshapes:

- **More use-site types**: config templating — a generated render unit
  expanding secret references into a config file — would be a new enum value
  with its own option group, exactly like `env-wrapper` slots beside
  `credential` today. Thanks to the defaults, the common env case is one
  line:

  ```nix
  # exports GRAFANA_ADMIN_PASSWORD, loads credential "grafana-admin-password"
  fleet.secrets.grafana-admin-password.use.carbon.services.grafana.type = "env-wrapper";
  ```
- **More use kinds beside `services`**: `use.<host>.podman.<container>`
  bridging into podman-secrets; possibly other non-systemd consumers.
- **`schema.fleet.services`**: a higher-level den-style service layer that
  emits `fleet.secrets` entries programmatically. This is why the registry
  is plain host-agnostic data with no required human judgement per entry:

  ```nix
  fleet.secrets."${svc.name}-db-password" = {
    origin = svc.host;
    generator = "openssl rand -hex 32";
    use.${svc.host}.services.${svc.unit} = {};
  };
  ```

  Patterns it will lean on (verified against today's gio.services usage):
  shared external secrets declared once with use-sites across many services
  (one `fastmail-smtp-password`, per-site `env-wrapper.variable`); `_FILE`-style
  config rendered from `.path` (computable from registry data); all-hosts
  secrets via `use = lib.genAttrs <den host names> ...` (plain data — the
  consul encrypt key case); migration adoption — a fleet.secret named after
  an existing credstore blob adopts it (`ConditionPathExists` gating), so
  carbon/gallium services migrate without re-provisioning. Database
  passwords stay a non-case: postgres uses peer auth throughout.

## Implementation notes (for the build-out pass)

- Use-site option group per `type` (only the active type's group is read);
  v1 ships all three types; future types extend the enum additively.
- `generator.script` is the standard NixOS multi-form pattern:
  `types.oneOf [str path package]` normalized in one place —
  `lib.isDerivation v → lib.getExe v` (mainProgram), Nix path → run
  directly, string → `writeShellApplication` with `generator.path` as
  `runtimeInputs`. Whole-generator shorthand is `types.coercedTo` from the
  same three forms to `{ script = v; }` (check `isDerivation` BEFORE
  attrset/submodule — derivations are attrsets).
- **Push identity (v1 scope, decided)**: the dedicated credsync SSH identity
  from the credsync TODO list ships WITH v1, not later. Per-host keypair
  generated at first boot (wg-nfs-keygen pattern), private key in the
  credstore; pubkey registered in homelab.toml (same print-and-paste loop as
  the wg mesh keys); receiving hosts get a forced-command `authorized_keys`
  entry locked to `credsync write` (parse `SSH_ORIGINAL_COMMAND`), ideally
  under a dedicated user rather than root. Pushes can deliver secrets and
  nothing else. Destinations derive from homelab.toml machine addresses
  (`<host>.gio.ninja`).
- credsync currently activates `credsync-<name>.target`; rename to
  `secret-<name>.target` (or make the prefix configurable) so the script and
  this system agree.
- Manual provisioning needs no new tooling: `credsync write <name>` already
  reads stdin, encrypts into the credstore, and signals the target.
- **No escaped unit names, ever**: secret names are asserted to
  `^[a-z0-9-]+$` (hostnames already conform), so every derived unit name —
  `secret-provision-<name>`, `secret-push-<name>@<host>`, `secret-<name>` —
  is literal and typeable, never systemd-`\x2d`-escaped. The same charset
  applies to `credential.name` overrides (valid credential IDs).
- **`--name` binding is auto-handled**: systemd-creds embeds the credential
  name in encrypted blobs and validates it on load, which would break
  `credential.name` renames (`LoadCredentialEncrypted=<alias>:<secret>`).
  The pipeline owns both ends, so it handles this internally — either
  credsync encrypts without name binding (`--name=` empty) or verification
  shows mismatched IDs are tolerated; whichever way, renames just work and
  the user never sees the knob.
- Login warning plumbing: agetty picks up `/run/issue.d/*.issue` natively;
  for ssh, verify NixOS's pam_motd config reads a runtime motd dir (or wire
  `users.motd`-adjacent pam options) — needs a quick check during build-out.
- `fleet.secrets.<name>.path` ambiguity (multiple sites on one host) is an
  eval error listing the sites; `.paths.<site>` always works.
- `generator.needs`: each needed secret must exist, share the deriving
  secret's `origin`, and the needs graph must be acyclic. The provision unit
  gets `LoadCredentialEncrypted=` per need plus `Requires=`/`After=` its
  target. (Rotation cascade — re-deriving when a needed secret changes — is
  future work alongside `secretctl rotate`.)
- `SetCredential=`/`SetCredentialEncrypted=` are deliberately NOT exposed:
  the value/blob lives in the unit file (Nix store — world-readable resp.
  rebuild-per-rotation), and their load-fallback behavior would let services
  run with default credentials, defeating the fail-loud target gating.
- Non-secret material (public keys etc.) rides the same encrypted pipeline
  unchanged — runtime loading is assumed always possible; no plaintext
  storage mode, no eval-time bridge.
- Eval-time assertions follow the ssh-access convention (eager `throw`s with
  a named offender, reading `config.den.hosts` at file scope for the host
  list): hostnames exist as den hosts; `origin` not in
  `copyTo`; `credential.name` unique per (host, unit);
  `credential.encrypted = false` requires `credential.source` (the credstore
  search would never find our encrypted blob as plaintext); warn/error on a
  `use` unit that doesn't exist in that host's `systemd.services`
  (attr-name check only — safe from recursion).

## Open / future

- [ ] `secretctl rotate <name>` — delete blob, re-run provision, re-push;
      must cascade through `generator.needs` dependents (re-derive publics
      when a private rotates).
- [ ] **Remote first-time provisioning UX** — a small script (likely a
      credsync subcommand, e.g. `credsync edit <name> [<origin>]`) run from a
      desktop: opens `$EDITOR` on a tempfile (git-commit style, with a
      `#`-comment header explaining what's being set — comments stripped on
      save), then pipes the result over SSH into `credsync write <name>` on
      the origin and reports the receiver's verdict. Tempfile in a private
      tmpdir (or tmpfs), shredded afterwards; abort on empty buffer like an
      empty commit message. With homelab.toml the origin argument can
      default from the fleet registry, so the fix-it command is just
      `credsync edit cloudflare-dns-token`. Every "unprovisioned" surface
      (provision unit failure, login warning, push failures) should print
      this exact command once it exists — copy-paste-to-fix.
- [ ] Config templating/rendering type via generated systemd units.
- [ ] `podman` use kind bridging into podman-secrets. **Blocks container
      services** (grist, windmill workers): LoadCredential reaches the
      host-side quadlet unit, but nothing carries the value into the
      container automatically.
- [ ] `reloadOnChange` beside `restartOnChange` (`try-reload-or-restart`)
      for consul/caddy-style consumers.
- [ ] Byte-exact/binary credentials (inherits credsync's caveat).
