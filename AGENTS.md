# AGENTS.md

Guide for agentic coding tools working in this NixOS configuration repository.

## Build/Lint/Test Commands
- `nix flake check` - Validate all configurations (run before commits)
- `nom build .#nixosConfigurations.<hostname>.config.system.build.toplevel` - Build specific host
- `./deploy.sh <hostname> <ssh_user@ip>` - Deploy configuration to remote machine
- `treefmt` - Auto-format Nix (alejandra) and Lua (stylua) files
- `treefmt --fail-on-change` - Check formatting (used in pre-commit hook)
- `statix check` - Lint Nix for anti-patterns (disables: repeated_keys, manual_inherit)
- `deadnix` - Find unused Nix code

## Repository Structure
- `nix/hosts/` - Per-machine configs (cadmium, carbon, gallium, thorium, calcium, cesium)
- `nix/modules/nixos/` - System-level NixOS modules
- `nix/modules/home/` - User-level Home Manager modules
- `nix/modules/common/` - Shared modules across platforms
- `nix/packages/` - Custom package definitions
- `nix/lib/` - Helper functions and utilities
- `homelab.toml` - Machine metadata and SSH keys
- `secrets/` - Age-encrypted secrets

## Host Types
- **carbon**: Main server with Prometheus, Grafana, and core services (NixOS)
- **gallium**: NAS with storage services (NixOS)
- **cadmium**: Main development desktop (NixOS)
- **thorium**: macOS machine (nix-darwin)
- **calcium**: WSL2 distro (NixOS-WSL)
- **cesium**: Chromebook travel machine (NixOS)

Networking: Servers on dedicated VLAN with Unifi VPN for remote access.

## Code Style Guidelines
- **Formatting**: Use alejandra for Nix, stylua for Lua (automated via treefmt)
- **Imports**: Use `let...in` pattern for complex imports; import modules via `flake.nixosModules.*`
- **Naming**: kebab-case for files/dirs, camelCase for Nix variables, snake_case in homelab.toml
- **Types**: No explicit type annotations in Nix (relies on attribute sets and lists)
- **Comments**: NO comments unless necessary (prefer self-documenting code)
- **Structure**: System in `nix/modules/nixos/`, user in `nix/modules/home/`, hosts in `nix/hosts/`
- **Security**: Never commit unencrypted secrets; use age encryption in `secrets/`
- **Module Pattern**: Import via Blueprint's flake outputs, use inline modules `({pkgs, ...}: {...})` for host-specific config
- **Testing**: Always run `nix flake check` and `treefmt` before committing
- **Technologies**: nixpkgs-unstable primary, nixpkgs-stable via `flake.nixosModules.nixpkgs-stable` for select packages

## Module System
- Base modules provide common functionality (basic-packages, basic-settings)
- Specialized modules for specific needs (code-editing-ai, monitoring, zfs-backup)
- Home Manager modules configure user environments
- Machine-specific configurations in `hosts/` import relevant modules

## Key Technologies
- **Blueprint**: Organizes flake structure cleanly
- **Home Manager**: User environment management
- **Disko**: Declarative disk partitioning
- **treefmt-nix**: Code formatting pipeline
- **ZFS**: Storage with automated snapshots and backups
- **prek**: Git hooks via git-hooks.nix (deadnix, statix, shellcheck, stylua, treefmt)

## Common Workflows
- **Add machine**: Create `nix/hosts/<hostname>/` with configuration.nix, hardware.nix; update homelab.toml; test with `nix flake check`
- **Modify system**: Edit `nix/modules/nixos/`, run `treefmt`, then `nix flake check`
- **Modify user env**: Edit `nix/modules/home/`, run `treefmt`, then `nix flake check`
- **Host-specific changes**: Edit `nix/hosts/<hostname>/`, always validate with `nix flake check`
- **Secret management**: Store secrets in `secrets/` with age encryption; SSH keys in homelab.toml; never commit unencrypted secrets

## Documentation
- `docs/adding-a-module.md` - End-to-end guide for adding new NixOS modules (DNS, reverse proxy, dashboard, secrets)
## Commit Messages
- One line, imperative mood, start with capital letter
- No prefixes (no `chore:`, `feat:`, `fix:`, etc.)
- No emojis
- Describe what the change does, not what you did
- Only add extra lines for genuinely complex changes that need explanation

**Good examples:**
```
Setup Jellyfin server
Add reverse proxy for hammond
Fix broken devshell
Update Nixpkgs and llm-agents
Remove obsolete Claude Code package
Enable the Nixd LSP in Neovim
```

**Bad examples:**
```
chore: update deps
feat(neovim): add lsp support
fixed the thing
WIP
```
