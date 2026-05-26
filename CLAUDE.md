# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Overview

This is a personal NixOS/Nix flake configuration repository that manages multiple machines across different platforms (NixOS, Darwin, WSL2). The repository uses the Blueprint flake organization pattern to structure configurations cleanly.

## Development Commands

### Building and Testing
- `nix flake check` - Validate all configurations and check for errors
- `nom build .#nixosConfigurations.<hostname>.config.system.build.toplevel` - Build a specific host configuration
- `./deploy.sh <hostname> <ssh_user@ip>` - Deploy configuration to remote machine

### Code Formatting and Linting
- `treefmt` - Format all code (Nix with alejandra, Lua with stylua)
- `treefmt --check` - Check formatting without making changes
- `treefmt --fail-on-change` - Exit with error if formatting changes needed
- `statix check` - Check for Nix anti-patterns (configured to disable "repeated_keys")
- `deadnix` - Find unused Nix code

### Git Hooks
The repository uses prek (via git-hooks.nix) for git hooks:
- Pre-commit/pre-push: Runs deadnix, statix, shellcheck, stylua, selene, lua-ls, treefmt

## Architecture

### Directory Structure
- `nix/` - All Nix configurations (managed by Blueprint)
  - `hosts/` - Per-machine configurations (cadmium, gallium, etc.)
  - `modules/` - Reusable NixOS and Home Manager modules
    - `nixos/` - System-level modules
    - `home/` - User-level modules
    - `common/` - Shared modules
  - `lib/` - Helper functions and utilities
  - `packages/` - Custom package definitions
- `homelab.toml` - Machine metadata and SSH keys
- `secrets/` - Age-encrypted secrets

### Host Types
- **cadmium**: Main development desktop (NixOS)
- **gallium**: NAS with storage services (NixOS)
- **thorium**: macOS machine (nix-darwin)
- **calcium**: WSL2 distro (NixOS-WSL)
- **cesium**: Chromebook travel machine (NixOS)

### Module System
The configuration uses a modular approach:
- Base modules provide common functionality (basic-packages, basic-settings)
- Specialized modules for specific needs (code-editing-ai, monitoring, zfs-backup)
- Home Manager modules configure user environments
- Machine-specific configurations in `hosts/` import relevant modules

### Blueprint

This repo uses [Blueprint](https://numtide.github.io/blueprint/main/getting-started/folder_structure/) to organize the flake. Blueprint autodetects files in conventional directories under a configurable prefix (here `nix/`) and maps them to flake outputs automatically — no manual wiring needed.

#### How Autodetection Works

Blueprint scans the `nix/` prefix directory for well-known folder names and file patterns. Each `.nix` file (or `<name>/default.nix` directory) found is automatically registered as a flake output:

| Directory | Flake Output | Purpose |
|-----------|-------------|---------|
| `hosts/<hostname>/configuration.nix` | `nixosConfigurations.<hostname>` | NixOS machine configs |
| `hosts/<hostname>/darwin-configuration.nix` | `darwinConfigurations.<hostname>` | macOS (nix-darwin) configs |
| `hosts/<hostname>/users/<username>.nix` | `homeConfigurations.<user>@<host>` | Home Manager user configs |
| `modules/nixos/<name>.nix` | `nixosModules.<name>` | NixOS modules |
| `modules/home/<name>.nix` | `homeModules.<name>` | Home Manager modules |
| `modules/darwin/<name>.nix` | `darwinModules.<name>` | nix-darwin modules |
| `modules/<other>/<name>.nix` | `modules.<other>.<name>` | Other module types |
| `packages/<pname>.nix` | `packages.<system>.<pname>` | Package definitions |
| `lib/default.nix` | `lib` | Shared Nix functions |
| `checks/<name>.nix` | `checks.<system>.<name>` | Flake checks |
| `templates/<name>/` | `templates.<name>` | Flake templates |
| `devshells/<name>.nix` | `devShells.<system>.<name>` | Dev environments |
| `formatter.nix` | `formatter.<system>` | Code formatter |
| `devshell.nix` | `devShells.<system>.default` | Default dev shell |

#### Arguments Passed to Files

Blueprint injects different arguments depending on the file type:

**Per-system args** (available to packages, checks, devshells, formatter):
- `inputs` — all flake inputs
- `flake` — self-reference (shorthand for `inputs.self`)
- `system` — current system string (e.g. `x86_64-linux`)
- `perSystem` — flake input packages filtered to current system
- `pkgs` — the configured nixpkgs instance

**Host configuration files** (`hosts/<hostname>/configuration.nix`, `darwin-configuration.nix`):
- `inputs`, `flake`, `perSystem`, `hostName`

**Home Manager user files** (`hosts/<hostname>/users/<username>.nix`):
- `inputs`, `flake`, `perSystem`, plus OS-specific args like `osConfig`
- `home.username` and `home.homeDirectory` default based on the file path

**Package files** (`packages/<pname>.nix`):
- All per-system args plus `pname` (derived from the filename)

**Library** (`lib/default.nix`):
- `inputs`, `flake` (not per-system — lib is system-independent)

**Modules** (`modules/**/*.nix`):
- Standard NixOS/Home Manager module arguments. If the module function accepts `flake` or `inputs` parameters, Blueprint auto-applies them before exposing the module.

#### Module Wrapping

If a module's top-level function accepts `flake` or `inputs` as parameters, Blueprint calls those automatically before exposing the module. This means modules can access flake inputs without the host needing to pass them through `specialArgs`.

### Key Technologies
- **Flake inputs**: Uses nixpkgs-unstable primary, nixpkgs-stable for select packages
- **Blueprint**: Organizes flake structure cleanly
- **Home Manager**: User environment management
- **Disko**: Declarative disk partitioning
- **treefmt-nix**: Code formatting pipeline
- **ZFS**: Storage with automated snapshots and backups

## Common Tasks

### Adding a New Machine
1. Create host directory in `nix/hosts/<hostname>/`
2. Add configuration.nix importing required modules
3. Add hardware.nix with hardware-specific settings
4. Update homelab.toml with machine metadata
5. Test with `nix flake check`

### Modifying Configurations
- System changes go in `nix/modules/nixos/`
- User environment changes go in `nix/modules/home/`
- Machine-specific changes go in `nix/hosts/<hostname>/`
- Always run `treefmt` before committing
- Use `nix flake check` to validate before pushing

### Secret Management
- Secrets stored in `secrets/` directory using age encryption
- SSH keys defined in homelab.toml for consistent access
- Never commit unencrypted secrets to the repository

### Nix Code Style
- Use `lib.pipe` for data transformations to improve readability
- Prefer `lib.pipe` over deeply nested function calls when processing data through multiple steps
- Example: `lib.pipe data [step1 step2 step3]` instead of `step3 (step2 (step1 data))`
- Prefer `pkgs.writeShellApplication` over `pkgs.writeShellScript`/`pkgs.writeShellScriptBin` unless there is a good reason not to (e.g. the script must not use `set -euo pipefail`)

## Git Commit Guidelines

### Commit Message Style
- Keep commit messages short and concise
- Use imperative mood ("Add feature" not "Added feature")
- No promotional text or tool references
- No "Co-Authored-By" lines

### Author and Committer
Always set both author and committer to the repository owner:
```bash
GIT_COMMITTER_NAME="Giovanni d'Amelio" \
GIT_COMMITTER_EMAIL="gio@damelio.net" \
git commit --author="Giovanni d'Amelio <gio@damelio.net>" -m "Commit message"
```

### Example Good Commit
```
Add whichbin script to lil-scripts

Adds whichbin utility that follows executable symlink chains to find the
actual binary location in the Nix store.
```
