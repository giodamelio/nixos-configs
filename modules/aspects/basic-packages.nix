# basic-packages — common CLI tooling installed on every host. Converted from
# nix/modules/nixos/basic-packages.nix.
#
# `perSystem` arrives as a module arg from the per-system aspect (see
# modules/aspects/per-system.nix, included in den.default). The repo's own
# packages (Blueprint `flake.packages.<sys>`) are reached as `perSystem.self`.
_: {
  den.aspects.basic-packages.nixos = {
    perSystem,
    pkgs,
    ...
  }: let
    flakePkgs = perSystem.self;
    customNeovim = perSystem.neovim-configs.light;
    inherit (perSystem) giopkgs;
  in {
    environment = {
      systemPackages = with pkgs; [
        zsh # Better default shell
        ripgrep # Better grep
        fd # Better find
        htop # Better top
        btop # High level system resources overview
        tree # I always want this...
        zellij # Kinda like Tmux
        # usbutils # For lsusb command
        flakePkgs.witr # Why is this process/port/whatever running
        flakePkgs.set-terminal-title # Set terminal title via escape sequence
        jq # JSON munging

        git
        file
        zip
        unzip

        # My custom wrapped Neovim with configs/plugins
        customNeovim

        # Internet fetchers
        curl
        wget
        xh

        rage # Easy encryption
        flakePkgs.systemd-creds-edit # Edit systemd-creds encrypted credentials in place
        cachix # Nix binary caching
        attic-client # Nix binary cache
        nix-output-monitor # Pretty cli output for Nix commands
        giopkgs.e2ecp # Easy cross computer file transfer. CLI or Browser
      ];
    };
  };
}
