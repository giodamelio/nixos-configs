# Adding a New NixOS Module

This guide covers the end-to-end process for adding a new NixOS module to this repository, including DNS, reverse proxy, dashboard, and secret management.

> **Sections 1-8 below are Blueprint-era and superseded.** They describe the old
> `nix/` tree: `nix/modules/nixos/`, `flake.nixosModules.*`, `gio.credentials`,
> hand-written `homelab.toml` CNAMEs, and `/etc/credstore.encrypted`. All six NixOS
> hosts are on den now. Write new work against "den aspects" immediately below;
> keep the old sections only for reading pre-migration code.

## den aspects (current)

### Where files go

`import-tree` loads everything under `modules/`, so a new file is picked up with no
registration. Files starting with `_` are skipped — use that for helpers a module
imports directly (`_service.nix`, `_lib.nix`).

- shared, opt-in feature -> `modules/aspects/<area>/<name>.nix`, attached by adding
  `den.aspects.<name>` to a host's `includes`
- one host's copy of a service -> `modules/hosts/<host>/<service>.nix`

New files must be visible to git before Nix sees them. `jj status` snapshots the
working copy, which is enough.

### Exposing a service

Declare the endpoint on the host entity. The Caddy vhost **and** the DNS record both
render from it — do not touch `homelab.toml`, whose `cname` block is dead for den
services:

```nix
den.hosts.<system>.<host>.services.<name> = {
  endpoint = {
    domain = "<subdomain>";
    backend.host = "localhost";
    backend.port = <port>;
  };
  healthcheck.target = "https://<subdomain>.gio.ninja/-/healthy";
};
```

`domain` may contain dots. `domain = "prometheus.rhodium"` renders
`prometheus.rhodium.gio.ninja. IN A <host ip>` correctly — verified against dns.nix.
That is how to run several instances of one service across the fleet, since endpoint
domains must be unique fleet-wide (there is an assertion for it).

Consul registration is on by default per service but self-gates on
`host.consul.enable`, and only reads the **local** host's services — so it is inert
on hosts without a Consul agent.

### Secrets

Blobs live in `/usr/lib/credstore.encrypted` and are delivered by agevault. Names
are snake_case; a dash is a hard eval error.

Prefer `needs` — the service reads the credential path itself:

```nix
fleet.credentials.needs = ["service_api_key"];
# available at /run/credentials/<unit>.service/service_api_key
```

Most software supports this: look for a `*_file` / `*File` setting (garage's
`rpc_secret_file`, Perses' `passwordFile`, miniflux's `*_FILE` vars). Use
`unit_wrappers` only when a program can *just* read an environment variable:

```nix
fleet.credentials.unit_wrappers.<unit>.environment.<VAR> = "service_api_key";
```

That one line adds the name to `needs`, attaches `LoadCredentialEncrypted`, and
generates an `ExecStart`-wrapping drop-in that exports the value.

**`EnvironmentFile=` cannot read `/run/credentials`.** systemd loads environment
files when it spawns each `Exec*` line, *before* that invocation's credentials
exist, so the path is always missing and the unit fails with `Failed to load
environment files: No such file or directory`. This silently broke gallium's atticd
for weeks. If a service only accepts an env *file*, stage it with `ExecStartPre`
into a `RuntimeDirectory` and point `EnvironmentFile=-` at that (the `-` matters:
the file does not exist yet when `ExecStartPre` itself is spawned).

### Modular services (RFC 163)

For software that needs several independent instances on one host. See
`modules/aspects/server/caddy/` and `modules/aspects/monitoring/telegraf/`: a
`_service.nix` modelling one instance (`_class = "service"`, options,
`process.argv`), plus a thin aspect exposing `gio.<name>.instances` as
`lazyAttrsOf deferredModule` and mapping them into `system.services.<name>`.

Three things that cost time:

- **The instance name becomes the unit name.** caddy prefixes (`caddy-<name>`);
  telegraf does not, so existing unit names survive a conversion. Pick deliberately.
- **The framework already defaults `wantedBy`, `Type`, `Restart` and `RestartSec`**
  as `mkDefault`. Repeating them in your service module *collides* at equal priority
  rather than overriding, and eval fails. Only set what the framework does not.
- **`ExecStart` renders as a one-element list**, not a string, because
  `service.nix` builds `ExecStart = [ mainExecStart ... ]`. Anything reading it back
  (like the credential wrapper) must handle both forms.

Per-instance state is *not* automatic. `DynamicUser` gives separate UIDs, not
separate directories — set `StateDirectory` per instance in the thin aspect, which
is the only place that knows the instance name.

### Verifying

```bash
prek run -a       # the repo's checks (treefmt, statix, deadnix, shellcheck, ...)
nix eval '.#nixosConfigurations.<host>.config.system.build.toplevel.drvPath'
```

Evaluating is not building, and neither proves runtime behaviour. Sandbox settings
in particular only fail on the host — `RestrictAddressFamilies` without `AF_NETLINK`
silently broke telegraf's `net` input, which needs netlink to enumerate interfaces.

## 1. Create the Module

Create a new file in `nix/modules/nixos/<module-name>.nix`:

```nix
{
  services.<service-name> = {
    enable = true;
    # service configuration
  };
}
```

**Blueprint auto-discovery**: Dropping a `.nix` file in `nix/modules/nixos/` automatically exposes it as `flake.nixosModules.<module-name>`. No manual registration required.

## 2. Import into Host Configuration

In `nix/hosts/<hostname>/configuration.nix`, add the module to the imports list:

```nix
{flake, ...}: {
  imports = [
    # ... existing imports
    flake.nixosModules.<module-name>
  ];
}
```

For host-specific configuration that wraps a module, create a separate file (e.g., `nix/hosts/<hostname>/<service>.nix`) and import it:

```nix
{flake, ...}: {
  imports = [
    flake.nixosModules.<module-name>
  ];

  # host-specific overrides
}
```

## 3. Add DNS Entry

Edit `homelab.toml` to add a CNAME entry pointing to the host:

```toml
[dns."gio.ninja".cname]
"<hostname>.lan." = [
  # ... existing entries
  "<subdomain>",
]
```

The `lan-dns.nix` module generates CoreDNS zone files from these entries at evaluation time.

## 4. Configure Reverse Proxy

For HTTPS access, use `services.gio.reverse-proxy.virtualHosts`:

```nix
services.gio.reverse-proxy = {
  enable = true;
  virtualHosts.<subdomain> = {
    host = "localhost";
    port = <port>;
  };
};
```

This generates a Caddy vhost at `https://<subdomain>.gio.ninja` with automatic Cloudflare DNS-01 TLS certificates.

## 5. Add to Homer Dashboard

Edit `nix/hosts/carbon/homer.nix` to add the service to the dashboard:

```nix
{
  name = "<Service Name>";
  subtitle = "<Description>";
  url = "https://<subdomain>.gio.ninja";
  logo = dashboardLogo "<icon-name>";
}
```

- User-facing services go in `settings.services[].items`
- Admin/infrastructure services go in `adminSettings.services[].items`

Icon names come from [walkxcode/dashboard-icons](https://github.com/walkxcode/dashboard-icons).

## 6. Register with Consul

For service discovery and health monitoring:

```nix
gio.services.<name>.consul = {
  name = "<name>";
  address = "<subdomain>.gio.ninja";
  port = 443;
  checks = [
    {
      http = "https://<subdomain>.gio.ninja";
      interval = "60s";
    }
  ];
};
```

## 7. Manage Secrets

> **Rewritten 2026-08-23.** `gio.credentials` is dead in the den tree, and
> hand-running `systemd-creds encrypt` is no longer how secrets get onto a host.
> Design: `docs/pi-ca-secrets-plan.md`. Migration: `MIGRATION.md`.

Declare the use-site in `fleet.secrets`; the aspect emits the systemd wiring:

```nix
fleet.secrets.<secret_name>.use.<host>.services.<unit> = {
  type = "credential"; # or "env-wrapper"
};
```

That generates a drop-in carrying `LoadCredentialEncrypted=<secret_name>`, plus a
`secret-<secret_name>.path` -> `.target` pair that holds the unit until the blob
exists. At runtime the value is at
`/run/credentials/<unit>.service/<secret_name>`.

### Name the secret correctly

**snake_case only** — `[a-z0-9_]+`, no `-` and no `.`.

The name is also the blob name **and** the credential id. agevault writes blobs
with the name embedded, and systemd refuses to load a named blob under a
different id, so any mismatch is a hard failure at unit start. Do not set
`credential.name` to something the vault cannot express; if a program demands a
particular id (a `.json` extension, say), fix it at the consumer — see "The three
consumers that force a rename" in `docs/pi-ca-secrets-plan.md`.

### Get the value onto the host

Do not create secrets yourself. The operator adds it to the offline vault and
pushes it:

```bash
# in the secrets repo
agevault write <host> <secret_name> -    # byte-exact from stdin
agevault generate-toml                   # refresh the committed manifest
agevault push <host> <secret_name>       # decrypt locally -> systemd-creds encrypt over ssh
```

`push` reports `updated` or `unchanged` per secret, so re-running it is also how
you confirm the vault matches the host.

Note the manifest (`secrets.toml`) must be regenerated and committed, or the
build fails: `fleet.credentials` asserts at eval time that every declared need
exists in the manifest for that host.

This keeps config files as static nix store derivations and loads only the secret
value at runtime.

## 8. Verification

Before committing, run:

```bash
treefmt                  # Format Nix and Lua files
statix check             # Lint for Nix anti-patterns
deadnix                  # Find unused Nix code
nix flake check          # Validate all configurations build
```

## Module Patterns

### Simple Module (No Options)

Bare config, just import and it works:

```nix
{
  services.foo.enable = true;
  services.foo.setting = "value";
}
```

### Host-Specific Wrapper

When a module needs host-specific config:

```nix
# nix/hosts/<hostname>/<service>.nix
{flake, ...}: {
  imports = [flake.nixosModules.<module>];

  # host-specific additions
  services.foo.extraSetting = "host-value";
}
```

### Parent/Child Pattern

For distributed services (like Netdata streaming):

- `nix/modules/nixos/<service>-parent.nix` — server role
- `nix/modules/nixos/<service>-child.nix` — client role

Import the appropriate module based on the host's role.
