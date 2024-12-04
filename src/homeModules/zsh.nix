_: {
  lib,
  pkgs,
  ...
}: {
  programs.zsh = {
    enable = true;
    enableCompletion = true;

    # Setup Homebrew path on MacOS
    initExtra = lib.mkIf pkgs.stdenv.hostPlatform.isDarwin ''
      eval "$(/opt/homebrew/bin/brew shellenv)"
    '';
  };

  programs.zoxide = {
    enable = true;
    enableZshIntegration = true;
  };

  programs.starship = {
    enableZshIntegration = true;
  };

  programs.nnn = {
    enable = true;
  };

  programs.direnv = {
    enable = true;
    enableBashIntegration = true;
    enableZshIntegration = true;
    nix-direnv.enable = true;
  };
}
