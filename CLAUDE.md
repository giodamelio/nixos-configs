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
The repository uses lefthook for git hooks:
- Pre-commit: Runs `treefmt --fail-on-change` on Nix and Lua files
- Pre-push: Runs `nix flake check`

## Architecture

### Directory Structure
- `nix/` - All Nix configurations (managed by Blueprint)
  - `hosts/` - Per-machine configurations (cadmium, lithium1, gallium, etc.)
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
- **lithium1**: Headscale gateway VPS (NixOS) 
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