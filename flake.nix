{
  description = "My Personal Nix Configs";

  outputs = inputs:
    inputs.blueprint {
      inherit inputs;
      prefix = ./nix;
      nixpkgs.config.allowUnfree = true;
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

    # Neovim config framework
    nvf.url = "github:notashelf/nvf";
    nvf.inputs.nixpkgs.follows = "nixpkgs";

    # Automated Git hooks
    pre-commit-hooks.url = "github:cachix/git-hooks.nix";
    pre-commit-hooks.inputs.nixpkgs.follows = "nixpkgs";

    # Additional Helpful Std library
    nix-std.url = "github:chessai/nix-std";

    # Awesome Launcher Program (Like Raycast)
    vicinae.url = "github:vicinaehq/vicinae";
    vicinae.inputs.nixpkgs.follows = "nixpkgs";
    vicinae-extensions.url = "github:vicinaehq/extensions";
    vicinae-extensions.inputs.nixpkgs.follows = "nixpkgs";
    vicinae-extensions.inputs.vicinae.follows = "vicinae";

    # Define/Run Podman quadlets easily
    quadlet-nix.url = "github:SEIAROTg/quadlet-nix";

    # Unison Programming Language
    unison-lang.url = "github:giodamelio/unison-nix/giodamelio/init-ucm-desktop";
    unison-lang.inputs.nixpkgs.follows = "nixpkgs";

    # LLM Agents
    llm-agents.url = "github:numtide/llm-agents.nix";
    llm-agents.inputs.nixpkgs.follows = "nixpkgs";

    # Fork of OpenAI Codex
    just-every-code.url = "github:just-every/code";
    just-every-code.inputs.nixpkgs.follows = "nixpkgs";

    # Handy Speach to Text
    handy.url = "github:cpuguy83/nix-handy-stt/upstream_pr_680";
  };
}
