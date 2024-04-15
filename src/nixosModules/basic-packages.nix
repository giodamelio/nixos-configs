{root, ...}: {pkgs, ...}: let
  customNeovim = root.packages.neovim {inherit pkgs;};
  open-ports = pkgs.writeShellApplication {
    name = "open-ports";
    runtimeInputs = with pkgs; [lsof ripgrep];
    text = ''
      output=$(sudo lsof -i -P -n)

      # Print the column labels
      echo "$output" | head -n 1

      # Print just the open listening ports
      echo "$output" | rg "LISTEN"
    '';
  };
in {
  environment = {
    systemPackages = with pkgs; [
      zsh # Better default shell
      ripgrep # Better grep
      fd # Better find
      htop # Better top
      tree # I always want this...

      git
      file

      # My custom wrapped Neovim with configs/plugins
      customNeovim

      # Small script to list the processes that are listening on ports
      open-ports

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
