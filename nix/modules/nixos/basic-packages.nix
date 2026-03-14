{
  perSystem,
  pkgs,
  flake,
  ...
}: let
  flakePkgs = flake.packages.${pkgs.stdenv.hostPlatform.system};
  customNeovim = perSystem.neovim-configs.default;
  inherit (perSystem) giopkgs;
in {
  environment = {
    systemPackages = with pkgs; [
      zsh # Better default shell
      ripgrep # Better grep
      fd # Better find
      htop # Better top
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
      cachix # Nix binary caching
      devenv # Easy development environment management
      attic-client # Nix binary cache
      nix-output-monitor # Pretty cli output for Nix commands
      giopkgs.e2ecp # Easy cross computer file transfer. CLI or Browser
    ];
  };
}
