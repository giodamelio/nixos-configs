{
  pkgs,
  lib,
  ...
}: let
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
      zellij # Kinda like Tmux
      usbutils # For lsusb command
      dogdns # Improved dns record fetcher

      git
      file

      # My custom wrapped Neovim with configs/plugins
      giodamelio.neovim

      # Small script to list the processes that are listening on ports
      open-ports

      # Internet fetchers
      curl
      wget
      xh

      rage # Easy encryption
      cachix # Nix binary caching
    ];
  };
}
