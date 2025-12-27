{
  pkgs,
  flake,
  ...
}: let
  flakePkgs = flake.packages.${pkgs.stdenv.hostPlatform.system};
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

      git
      file

      # My custom wrapped Neovim with configs/plugins
      flakePkgs.neovim

      # Internet fetchers
      curl
      wget
      xh

      rage # Easy encryption
      cachix # Nix binary caching
      devenv # Easy development environment management
      attic-client # Nix binary cache
      nix-output-monitor # Pretty cli output for Nix commands
    ];
  };
}
