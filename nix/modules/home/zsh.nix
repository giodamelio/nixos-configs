{
  flake,
  pkgs,
  lib,
  config,
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
      # Fix Vim Mode keybindings issue
      # See: https://github.com/jeffreytse/zsh-vi-mode/issues/148#issuecomment-1566863380
      vimModeKeybindingFix = lib.mkAfter ''
        zvm_after_init_commands+=("bindkey -M viins '^r' atuin-search-viins")
      '';

      # Add some things to the path
      homebrewShellEnv = lib.mkIf pkgs.stdenv.hostPlatform.isDarwin (let
        brewBinPath = flake.outputs.darwinConfigurations.thorium.config.homebrew.brewPrefix;
        # The one from nix-darwin has the /bin attached, remove that
        brewPrefix = builtins.dirOf brewBinPath;
      in
        lib.mkAfter ''
          # Setup Homebrew path on MacOS
          # Set the homebrew PATH after the NIX path so Nix executables take precedent
          # Not using `brew shellenv` since it always puts itself first in the $PATH
          # Note: Hostname has to be hardcoded for now
          # See: https://github.com/numtide/blueprint/issues/69
          export HOMEBREW_PREFIX="${brewPrefix}";
          export HOMEBREW_CELLAR="${brewPrefix}/Cellar";
          export HOMEBREW_REPOSITORY="${brewPrefix}";
          export PATH="$PATH:${brewPrefix}/bin";
          export INFOPATH="${brewPrefix}/share/info:${"\${INFOPATH:-}"}";

          # Add ~/.local/bin to the start of the PATH
          # ''\ is a weird escape sequence
          export PATH="''\${HOME}/.local/bin:$PATH"

          # Add ~/bin to the start of the path
          export PATH="''\${HOME}/bin:$PATH"
        '');

      # Load some secrets from the MacOS keychain
      loadSecrets = lib.mkOrder 1400 ''
        export OPENAI_API_KEY=$(security find-generic-password -a "$USER" -s 'openai_api_token' -w)
      '';

      # A function to invoke Yazi with the extra power of changing directory on output
      # 1100 is aliases
      yaziFunction = lib.mkOrder 1101 ''
        function y() {
          local tmp="$(mktemp -t "yazi-cwd.XXXXXX")" cwd
          ${pkgs.lib.getExe pkgs.yazi} "$@" --cwd-file="$tmp"
          IFS= read -r -d "" cwd < "$tmp"
          [ -n "$cwd" ] && [ "$cwd" != "$PWD" ] && builtin cd -- "$cwd"
          rm -f -- "$tmp"
        }
      '';
    in
      lib.mkMerge (
        [vimModeKeybindingFix yaziFunction]
        ++ (lib.optionals pkgs.stdenv.hostPlatform.isDarwin [homebrewShellEnv loadSecrets])
      );
  };

  programs.zoxide = {
    enable = true;
    enableZshIntegration = true;
  };

  programs.starship = {
    enableZshIntegration = true;
  };

  programs.direnv = {
    enable = true;
    enableBashIntegration = true;
    enableZshIntegration = true;
    nix-direnv.enable = true;
  };
}
