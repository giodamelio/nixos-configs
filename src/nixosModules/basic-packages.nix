{...}: {
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
      git
      neovim
      file

      # Internet fetchers
      curl
      wget
      xh
    ];
  };
}
