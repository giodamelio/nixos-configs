{
  pkgs,
  lib,
  ...
}: {
  programs.zsh = {
    enable = true;
    enableCompletion = true;

    plugins = [
      # Improved VIM mode
      {
        name = "vi-mode";
        src = pkgs.zsh-vi-mode;
        file = "share/zsh-vi-mode/zsh-vi-mode.plugin.zsh";
      }
    ];

    initContent = let
      # Setup Homebrew path on MacOS
      homebrewShellEnv = lib.mkAfter ''
        eval "$(/opt/homebrew/bin/brew shellenv)"
      '';

      # Fix Vim Mode keybindings issue
      # See: https://github.com/jeffreytse/zsh-vi-mode/issues/148#issuecomment-1566863380
      vimModeKeybindingFix = lib.mkAfter ''
        zvm_after_init_commands+=("bindkey -M viins '^r' atuin-search-viins")
      '';
    in
      lib.mkMerge (
        [vimModeKeybindingFix]
        ++ (lib.optionals pkgs.stdenv.hostPlatform.isDarwin [homebrewShellEnv])
      );
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
