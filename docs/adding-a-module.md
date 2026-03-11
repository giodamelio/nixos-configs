# Adding a New NixOS Module

This guide covers the end-to-end process for adding a new NixOS module to this repository, including DNS, reverse proxy, dashboard, and secret management.

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

For services requiring secrets, use `gio.credentials`:

```nix
gio.credentials = {
  enable = true;
  services.<service-name>.loadCredentialEncrypted = ["<credential-name>"];
};
```

This creates a systemd dropin with `LoadCredentialEncrypted=<credential-name>`. The credential file is available at runtime at `/run/credentials/<service-name>.service/<credential-name>`.

### Creating Encrypted Credentials

Do not create secrets yourself. Document the commands the user needs to run on the target machine:

```bash
# Create the credential content
echo "secret-value" > /tmp/credential-content

# Encrypt and place in credstore
sudo systemd-creds encrypt --name=<credential-name> /tmp/credential-content /etc/credstore.encrypted/<credential-name>

# Clean up
rm /tmp/credential-content
```

Include these instructions in your module's PR description or deployment notes so the operator can generate and store the secrets on each target machine.

This keeps config files as static nix store derivations and loads only the secret value at runtime.

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
