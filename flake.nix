{
  description = "My Personal Nix Configs";

  outputs = inputs: let
    # Blueprint owns most outputs (hosts, packages, modules, devshells, ...).
    bp = inputs.blueprint {
      inherit inputs;
      prefix = ./nix;
      nixpkgs.config.allowUnfree = true;
    };

    # den (a flake-parts module) owns, incrementally, the `nixosConfigurations`
    # of migrated hosts. See the migration plan + https://github.com/denful/den.
    fp = inputs.flake-parts.lib.mkFlake {inherit inputs;} (inputs.import-tree ./modules);
  in
    # Explicit ownership ledger — keep this carve LOUD (no recursiveUpdate). Move
    # keys here as migration phases complete; "who owns what" is answerable here.
    # Blueprint's `modules.*` output passes through untouched (den publishes none).
    bp
    // {
      # den wins for any host it defines; Blueprint keeps the rest.
      nixosConfigurations = bp.nixosConfigurations // fp.nixosConfigurations;

      # Same deal per system for packages and checks: den wins per name.
      packages =
        builtins.mapAttrs
        (system: bpPkgs: bpPkgs // (fp.packages.${system} or {}))
        bp.packages;
      checks =
        builtins.mapAttrs
        (system: bpChecks: bpChecks // (fp.checks.${system} or {}))
        bp.checks;
    }
    # Add the inputs to the outputs for easy access in `nix repl`;
    // {inherit inputs;};

  inputs = {
    # Nixpkgs
    nixpkgs.url = "flake:nixpkgs/nixpkgs-unstable";
    nixpkgs-stable.url = "github:nixos/nixpkgs/nixos-25.05";

    # My own personal set of packages
    giopkgs.url = "github:giodamelio/giopkgs";

    # Make the organization of the flake easy
    blueprint.url = "github:numtide/blueprint";
    blueprint.inputs.nixpkgs.follows = "nixpkgs";

    # Configure MacOS via Nix
    nix-darwin.url = "github:LnL7/nix-darwin";
    nix-darwin.inputs.nixpkgs.follows = "nixpkgs";

    # Format all the things
    treefmt-nix.url = "github:numtide/treefmt-nix";

    # Build NixOS images
    nixos-generators.url = "github:nix-community/nixos-generators";
    nixos-generators.inputs.nixpkgs.follows = "nixpkgs";

    # NixOS modules for specific hardware
    nixos-hardware.url = "github:NixOS/nixos-hardware/master";

    # Declarative disk partitioning
    disko.url = "github:nix-community/disko";
    disko.inputs.nixpkgs.follows = "nixpkgs";

    # Manage user environments with Nix
    home-manager.url = "github:nix-community/home-manager";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";

    # Pre built Nixpkgs index
    nix-index-database.url = "github:nix-community/nix-index-database";
    nix-index-database.inputs.nixpkgs.follows = "nixpkgs";

    # Use NixOS inside WSL2
    nixos-wsl.url = "github:nix-community/NixOS-WSL/main";
    nixos-wsl.inputs.nixpkgs.follows = "nixpkgs";

    # Secrets
    lilvault.url = "github:giodamelio/lilvault";
    lilvault.inputs.nixpkgs.follows = "nixpkgs";

    # My Personal Neovim Configuration
    neovim-configs.url = "github:giodamelio/neovim-configs-nix";
    neovim-configs.inputs.nixpkgs.follows = "nixpkgs";

    # Additional Helpful Std library
    nix-std.url = "github:chessai/nix-std";

    # Extensions for an Awesome Launcher Program (Like Raycast)
    vicinae-extensions.url = "github:vicinaehq/extensions";
    vicinae-extensions.inputs.nixpkgs.follows = "nixpkgs";

    # Define/Run Podman quadlets easily
    quadlet-nix.url = "github:SEIAROTg/quadlet-nix";

    # Unison Programming Language
    unison-lang.url = "github:ceedubs/unison-nix";
    unison-lang.inputs.nixpkgs.follows = "nixpkgs";

    # LLM Agents
    llm-agents.url = "github:numtide/llm-agents.nix";
    # llm-agents.inputs.nixpkgs.follows = "nixpkgs";

    # Fork of OpenAI Codex
    just-every-code.url = "github:just-every/code";
    just-every-code.inputs.nixpkgs.follows = "nixpkgs";

    # Handy Speach to Text
    handy.url = "github:cjpais/Handy";
    handy.inputs.nixpkgs.follows = "nixpkgs";

    # Run small declarative VMs easily
    microvm.url = "github:microvm-nix/microvm.nix";
    microvm.inputs.nixpkgs.follows = "nixpkgs";

    # Pull based deploy NixOS deploy tool
    comin.url = "github:nlewo/comin";
    comin.inputs.nixpkgs.follows = "nixpkgs";

    # Nix Module Options search based directly on modules themselves
    optnix.url = "sourcehut:~watersucks/optnix";
    optnix.inputs.nixpkgs.follows = "nixpkgs";

    # Physical boot selector switch via EFI shim
    boot-selector-switch.url = "github:giodamelio/boot-selector-switch";
    boot-selector-switch.inputs.nixpkgs.follows = "nixpkgs";

    # Interactively split jj changes into hunks
    jj-hunk.url = "github:laulauland/jj-hunk";
    jj-hunk.inputs.nixpkgs.follows = "nixpkgs";

    # Bubblewrap sandbox wrapper library
    jail-nix.url = "sourcehut:~alexdavid/jail.nix";

    # Easy project devshells
    devenv.url = "github:cachix/devenv";

    # Terminal multiplexer in Zig
    zmx.url = "github:neurosnap/zmx";

    # Noctalia desktop shell (bar, launcher, notifications, lock screen)
    noctalia.url = "github:noctalia-dev/noctalia-shell";
    noctalia.inputs.nixpkgs.follows = "nixpkgs";

    # Niri Wayland compositor flake (NixOS + Home Manager modules)
    niri.url = "github:sodiboo/niri-flake";
    niri.inputs.nixpkgs.follows = "nixpkgs";

    # Mob - AI agent tool
    mob.url = "github:giodamelio/mob";
    mob.inputs.nixpkgs.follows = "nixpkgs";

    # Affinity Suite (Designer, Photo, Publisher) via Wine
    affinity-nix.url = "github:mrshmllow/affinity-nix";
    affinity-nix.inputs.nixpkgs.follows = "nixpkgs";
    # affinity-nix upstream pins flake-compat to the lix-project fork on
    # git.lix.systems, served as a tarball whose locked URL carries a `?rev=`
    # query that some evaluators (the gradient-worker) canonicalize away, breaking
    # the lock ("mismatch in field 'url'"). Point it at the canonical edolstra
    # flake-compat on GitHub instead — same API, github-type lock (no URL-query
    # mismatch), and no git.lix.systems dependency.
    affinity-nix.inputs.flake-compat.url = "github:edolstra/flake-compat";

    # Nix-native CI system
    # Pinned to a specific rev: HEAD moves fast and the API changes between
    # releases. This rev includes the Actions framework (send_web_request /
    # forge_status_report) used for deploy webhooks.
    gradient.url = "github:wavelens/gradient/6530b7aed15db4cc644669edb4b47db1c6dd65af";

    # flake-parts: den is built on top of it; we run it beside Blueprint
    flake-parts.url = "github:hercules-ci/flake-parts";
    flake-parts.inputs.nixpkgs-lib.follows = "nixpkgs";

    # Auto-import every module file under ./modules (den's fork)
    import-tree.url = "github:denful/import-tree";

    # den: aspect-oriented config framework we are incrementally migrating to
    den.url = "github:denful/den";

    # Personal fork of herdr — carries the bwrap agent-detection patch upstream,
    # so we override llm-agents' herdr src with this instead of patching.
    herdr.url = "github:giodamelio/herdr/jj-workspace-migration";
    herdr.flake = false;
  };
}
