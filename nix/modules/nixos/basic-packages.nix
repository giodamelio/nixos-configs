{
  pkgs,
  flake,
  ...
}: let
  customNeovim = flake.packages.${pkgs.stdenv.system}.neovim;
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

      git
      file

      # My custom wrapped Neovim with configs/plugins
      customNeovim

      # Internet fetchers
      curl
      wget
      xh

      rage # Easy encryption
      cachix # Nix binary caching
      devenv # Easy development environment management
    ];
  };
}
