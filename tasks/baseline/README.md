# Migration baseline derivations

Pre-migration `system.build.toplevel` derivation paths for the two server hosts,
captured while both are still **Blueprint-owned** (den does not yet define them).
These are the fixed reference for `check-drv-drift` at every migration task.

| Host | Command |
|------|---------|
| gallium | `nix path-info --derivation .#nixosConfigurations.gallium.config.system.build.toplevel` |
| carbon  | `nix path-info --derivation .#nixosConfigurations.carbon.config.system.build.toplevel` |

After a host is defined in den, re-run the command and diff against the path in
its `<host>.drv` file. Only **allowlisted** differences are acceptable:

- mTLS removal (carbon's dropped read-only Consul vhost)
- `gio.credentials` → `fleet.secrets` store-path churn
- den-aspect-induced option defaults

Captured on the `migrate-carbon` worktree, nixpkgs rev `cbb5cf3` (26.11.20260606).
