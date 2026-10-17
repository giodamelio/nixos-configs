# zsh — my zsh setup: vi-mode, zoxide, direnv, helper functions, and (Darwin
# only) Homebrew shellenv + keychain secrets. Converted from
# nix/modules/home/zsh.nix.
#   - `flake.outputs.darwinConfigurations.thorium` ->
#     `inputs.self.darwinConfigurations.thorium` via the file-scope `inputs`
#     closure. Only forced on Darwin (under `optionals isDarwin`), so on Linux
#     hosts the cross-host reference is never evaluated.
{
  inputs,
  den,
  ...
}: {
  den.aspects.zsh.includes = [den.aspects.devshell-completion-sync];

  den.aspects.zsh.homeManager = {
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
        {
          name = "fzf-tab";
          src = pkgs.zsh-fzf-tab;
          file = "share/fzf-tab/fzf-tab.plugin.zsh";
        }
      ];

      initContent = let
        # REMIND-ME-TO: Remove vim mode keybinding fix workaround nixpkg_version=nixpkgs-unstable:zsh-vi-mode@>=0.13.0
        vimModeKeybindingFix = lib.mkAfter ''
          zvm_after_init_commands+=("bindkey -M viins '^r' atuin-search-viins")
          zvm_after_init_commands+=("bindkey -M viins '^I' fzf-tab-complete")
        '';

        # Alt+R opens atuin scoped to the current directory
        atuinDirectorySearch = lib.mkAfter ''
          _atuin_search_directory_viins() {
            _atuin_search --keymap-mode=vim-insert --filter-mode=directory
          }
          zle -N atuin-search-directory-viins _atuin_search_directory_viins
          zvm_after_init_commands+=("bindkey -M viins '^[r' atuin-search-directory-viins")
        '';

        # Allow editing the current line in edit mode with Control+E
        vimModeEditInInsertMode = lib.mkAfter ''
          zvm_after_init_commands+=("bindkey -M viins '^E' zvm_vi_edit_command_line")
        '';

        # Add some things to the path
        homebrewShellEnv = lib.mkIf pkgs.stdenv.hostPlatform.isDarwin (let
          brewBinPath = inputs.self.darwinConfigurations.thorium.config.homebrew.brewPrefix;
          # The one from nix-darwin has the /bin attached, remove that
          brewPrefix = builtins.dirOf brewBinPath;
        in
          lib.mkAfter ''
            # Setup Homebrew path on MacOS
            # Set the homebrew PATH after the NIX path so Nix executables take precedent
            # Not using `brew shellenv` since it always puts itself first in the $PATH
            # REMIND-ME-TO: Stop hardcoding hostname issue_closed=github:numtide/blueprint#69
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

        # Create a directory (possibly several deep) and cd into it
        takeFunction = lib.mkOrder 1102 ''
          function take() {
            mkdir -p "$@" && cd "$@"
          }
        '';

        # Create a temporary directory and cd into it
        taketmpFunction = lib.mkOrder 1103 ''
          function taketmp() {
            cd "$(mktemp -d)"
          }
        '';

        # Zoxide: interactive mode when no args, otherwise normal behavior
        zoxideInteractive = lib.mkAfter ''
          function z() {
            if [[ $# -eq 0 ]]; then
              __zoxide_zi
            else
              __zoxide_z "$@"
            fi
          }
          function zi() {
            __zoxide_zi "$@"
          }
          [[ -o zle ]] && compdef __zoxide_z_complete z
        '';

        devenvAutoActivation = lib.mkAfter ''
          if command -v devenv &> /dev/null; then
            eval "$(devenv hook zsh)"
          fi
        '';

        # Sources completions written by direnv's add_completion. Unloading
        # restores any completion the command had before (e.g. a global one);
        # new helper functions the script defined stay behind.
        direnvCompletions = lib.mkAfter ''
          typeset -ga _direnv_completions_loaded=()
          typeset -gA _direnv_completions_prev_comps=() _direnv_completions_prev_funcs=()
          _direnv_completions() {
            local state="''${DIRENV_ZSH_COMPLETIONS-}|''${DIRENV_ZSH_COMPLETIONS_HASH-}"
            [[ $state == ''${_direnv_completions_state-} ]] && return
            local name f comp
            for f in ''${(k)_direnv_completions_prev_funcs}; do
              functions[$f]=$_direnv_completions_prev_funcs[$f]
            done
            for name in $_direnv_completions_loaded; do
              if (( ''${+_direnv_completions_prev_comps[$name]} )); then
                compdef $_direnv_completions_prev_comps[$name] $name
              else
                compdef -d $name
              fi
            done
            _direnv_completions_loaded=()
            _direnv_completions_prev_comps=()
            _direnv_completions_prev_funcs=()
            _direnv_completions_state=$state
            for f in ''${(s.:.)''${DIRENV_ZSH_COMPLETIONS-}}; do
              name=''${''${f:t}#_}
              comp=''${_comps[$name]-}
              if [[ -n $comp ]]; then
                _direnv_completions_prev_comps[$name]=$comp
                (( ''${+functions[$comp]} )) && _direnv_completions_prev_funcs[$comp]=$functions[$comp]
              fi
              source $f
              _direnv_completions_loaded+=($name)
            done
          }
          autoload -Uz add-zsh-hook
          add-zsh-hook precmd _direnv_completions
        '';

        zmxCompletions = lib.mkAfter ''
          if command -v zmx &> /dev/null; then
            eval "$(zmx completions zsh)"
          fi
        '';
      in
        lib.mkMerge (
          [
            vimModeKeybindingFix
            atuinDirectorySearch
            vimModeEditInInsertMode
            yaziFunction
            takeFunction
            taketmpFunction
            zoxideInteractive
            devenvAutoActivation
            direnvCompletions
            zmxCompletions
          ]
          ++ (lib.optionals pkgs.stdenv.hostPlatform.isDarwin [homebrewShellEnv loadSecrets])
        );
    };

    programs.zoxide = {
      enable = true;
      enableZshIntegration = true;
      options = ["--no-cmd"];
    };

    # fzf-tab needs the binary; the shell integration would steal ^R from atuin
    programs.fzf = {
      enable = true;
      enableZshIntegration = false;
    };

    programs.starship = {
      enableZshIntegration = true;
    };

    programs.direnv = {
      enable = true;
      enableBashIntegration = true;
      enableZshIntegration = true;
      nix-direnv.enable = true;

      # Auto-redirect Cargo build output to a per-project dir on the
      # unsnapshotted ~/.cache/builds dataset for any project that has a
      # Cargo.toml. Runs on every direnv load (no per-.envrc line needed).
      # Keyed off the topmost ancestor holding a Cargo.toml — the workspace
      # root in the common case, so members share one target dir — with a path
      # hash to disambiguate same-named projects. Non-Rust dirs are left on the
      # global CARGO_TARGET_DIR fallback.
      stdlib = ''
        _cargo_auto_target() {
          local dir="$PWD" root=""
          while [ "$dir" != "/" ]; do
            [ -e "$dir/Cargo.toml" ] && root="$dir"
            dir="$(dirname "$dir")"
          done
          [ -n "$root" ] && export CARGO_TARGET_DIR="$HOME/.cache/builds/cargo/$(basename "$root")-$(printf '%s' "$root" | sha1sum | cut -c1-8)"
        }
        _cargo_auto_target

        # Usage: add_completion <command> <generator...>, e.g.
        #   add_completion restish restish completion zsh
        add_completion() {
          local name=$1
          shift
          local file
          file="$(direnv_layout_dir)/zsh-completions/_$name"
          mkdir -p "$(dirname "$file")"
          "$@" >"$file" || {
            rm -f "$file"
            log_error "add_completion $name: generator failed"
            return 1
          }
          export DIRENV_ZSH_COMPLETIONS="''${DIRENV_ZSH_COMPLETIONS:+$DIRENV_ZSH_COMPLETIONS:}$file"
          # The path stays the same across version bumps; the hash lets zsh see new content
          export DIRENV_ZSH_COMPLETIONS_HASH="''${DIRENV_ZSH_COMPLETIONS_HASH-}$(sha1sum "$file" | cut -c1-8)"
        }
      '';
    };
  };
}
