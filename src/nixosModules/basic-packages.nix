_: {
  config,
  lib,
  pkgs,
  ...
}: {
  environment = {
    systemPackages = with pkgs; [
      zsh # Better default shell
      ripgrep # Better grep
      fd # Better find
      htop # Better top

      git
      neovim
      file

      # Internet fetchers
      curl
      wget
      xh

      rage # Easy encryption
      cachix # Nix binary caching
    ];
  };

  programs.neovim = {
    enable = true;
    vimAlias = true;
    viAlias = true;
  };
}
