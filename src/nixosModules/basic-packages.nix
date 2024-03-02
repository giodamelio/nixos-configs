{root, ...}: {pkgs, ...}: let
  customNeovim = root.packages.neovim {inherit pkgs;};
in {
  environment = {
    systemPackages = with pkgs; [
      zsh # Better default shell
      ripgrep # Better grep
      fd # Better find
      htop # Better top

      git
      file

      # My custom wrapped Neovim with configs/plugins
      customNeovim

      # Install Kitty everywhere so the kitty terminfo is available
      kitty

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
