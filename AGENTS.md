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
- `docs/mtls.md` - mTLS client certificate authentication with step-ca and Caddy
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

# Ticket Management with tk

This project uses **tk** for ticket tracking. Tickets are stored as markdown files with YAML frontmatter in the `.tickets/` directory.

## Quick Reference

```bash
tk ready              # Find available work (no blockers)
tk show <id>          # View ticket details
tk start <id>         # Claim work (set status to in_progress)
tk close <id>         # Complete work (set status to closed)
tk ls --status=open   # List all open tickets
```

## Essential Commands

### Finding Work

- `tk ready` - Show open/in-progress tickets with all dependencies resolved (sorted by priority ascending, 0=highest)
- `tk ready --sort date` - Same, sorted by creation date (newest first)
- `tk show <id>` - Detailed ticket view with metadata and relationships
- `tk start <id>` - Set status to in_progress (claim work)
- `tk ls` - List all tickets
- `tk ls --status=open` - All open tickets
- `tk ls --status=in_progress` - Your active work
- `tk ls --status=closed` - Recently closed tickets
- `tk blocked` - Show open/in-progress tickets with unresolved dependencies
- `tk dep tree <id>` - Show dependency tree (deduplicates by default)
- `tk dep tree --full <id>` - Show full tree (all occurrences, no deduplication)

### Creating & Updating

- `tk new "Ticket title"` - Create a new ticket (defaults to status: open, type: task, priority: 2)
  - `--type=bug|feature|task|epic|chore` - Ticket type
  - `-p, --priority 0-4` - Priority (0=critical, 2=medium, 4=backlog)
  - `-d, --description "..."` - Description text
  - `-a, --assignee username` - Assign to someone
  - `--parent <id>` - Parent ticket ID
  - `--acceptance "..."` - Acceptance criteria
  - `--design "..."` - Design notes
  - `--external-ref "..."` - External reference (e.g., gh-123)
- `tk close <id>` - Set status to closed (mark complete)
- `tk reopen <id>` - Set status to open
- `tk note <id> "..."` - Append timestamped note to ticket
- `tk dep <id> <dependency-id>` - Add dependency (first ticket depends on second)
- `tk undep <id> <dependency-id>` - Remove dependency
- `tk link <id> <id> [id...]` - Create symmetric link between tickets (bidirectional)

### Querying & Filtering
- `tk query` - Output all tickets as JSON, one per line
- `tk query '.priority == "0"'` - Query with jq-style filters
- `tk query '.status == "open"'` - Find open tickets
- `tk query '.type == "bug"'` - Find bugs

### Maintenance
- `tk prune` - Dry-run: show dangling references (refs to deleted tickets)
- `tk prune --fix` - Actually remove dangling references from deps, links, and parent fields
  - Use case: After manually deleting ticket files (e.g., `rm .tickets/x-abc1.md`)
  - Ensures store consistency by cleaning up orphaned references

## Common Workflows

### Starting work:
```bash
tk ready              # Find available work
tk show <id>          # Review ticket details
tk start <id>         # Claim it
```

### Completing work:
```bash
tk close <id>         # Mark complete (can provide full or partial ID)
```

### Creating dependent tickets:
```bash
tk new "Implement feature X" --type=feature
tk new "Write tests for X" --type=task --parent=<feature-id>
tk dep <test-id> <feature-id>  # Tests depend on Feature (Feature blocks tests)
```

### Working with blocked tickets:
```bash
tk blocked            # See what's blocking progress
tk show <id>          # View dependencies preventing work
tk close <blocker-id> # Close the blocking ticket
```

## 🚨 CRITICAL 🚨

- **File issues for remaining work** - Create tickets with `tk new` for anything that needs follow-up
  - Create tickets for tracking strategic and/or discovered work (multi-session, dependencies, discovered work)
- **Update ticket status** - Close finished work with `tk close <id>`
  - Work is NOT complete until tickets are properly closed
  - NEVER leave work in ambiguous state (e.g., started but unclear if done)
  - Ticket state is the source of truth for project progress
