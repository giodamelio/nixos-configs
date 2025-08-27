{
  pkgs,
  lib,
  ...
}: let
  mkZellijPlugin = {
    name,
    version,
    url,
    hash,
  }:
    pkgs.stdenv.mkDerivation {
      pname = "zellij-${name}-plugin";
      inherit version;

      src = pkgs.fetchurl {
        inherit url hash;
      };

      dontUnpack = true;

      installPhase = ''
        mkdir -p $out/share/zellij/plugins
        cp $src $out/share/zellij/plugins/${name}.wasm
      '';

      meta = {
        description = "Zellij ${name} plugin";
        platforms = pkgs.lib.platforms.all;
      };
    };

  room-plugin = mkZellijPlugin {
    name = "room";
    version = "1.2.0";
    url = "https://github.com/rvcas/room/releases/download/v1.2.0/room.wasm";
    hash = "sha256-t6GPP7OOztf6XtBgzhLF+edUU294twnu0y5uufXwrkw=";
  };

  forgot = mkZellijPlugin {
    name = "forgot";
    version = "0.4.2";
    url = "https://github.com/karimould/zellij-forgot/releases/download/0.4.2/zellij_forgot.wasm";
    hash = "sha256-MRlBRVGdvcEoaFtFb5cDdDePoZ/J2nQvvkoyG6zkSds=";
  };

  zellijNavigator = mkZellijPlugin {
    name = "zellij-navigator";
    version = "0.3.0";
    url = "https://github.com/hiasr/vim-zellij-navigator/releases/download/0.3.0/vim-zellij-navigator.wasm";
    hash = "sha256-d+Wi9i98GmmMryV0ST1ddVh+D9h3z7o0xIyvcxwkxY0=";
  };
in {
  programs.zellij = {
    enable = true;
  };

  # Manually setup completions and not auto start
  # programs.zellij.enableZshIntegration just adds auto start
  programs.zsh.initContent = lib.mkOrder 551 ''
    eval "$(${lib.getExe pkgs.zellij} setup --generate-completion zsh)"
  '';

  # Manually set KDL config string, since the HM module is not in great shape right now
  xdg.configFile."zellij/config.kdl".text = let
    zellijNavigatorPath = "file:${zellijNavigator}/share/zellij/plugins/zellij-navigator.wasm";
    mkZellijBinding = binding: name: payload: ''
      bind "${binding}" {
          MessagePlugin "${zellijNavigatorPath}" {
              name "${name}";
              payload "${payload}";
          };
      }
    '';
  in ''
    keybinds {
      shared_except "locked" {
        bind "Ctrl y" {
          LaunchOrFocusPlugin "file:${room-plugin}/share/zellij/plugins/room.wasm" {
            floating true
            ignore_case true
            quick_jump true
          }
        }

        bind "Ctrl Alt y" {
          LaunchOrFocusPlugin "file:${forgot}/share/zellij/plugins/forgot.wasm" {
            "LOAD_ZELLIJ_BINDINGS" "true"
            floating true
          }
        }

        // Smart Split Manager
        ${mkZellijBinding "Ctrl h" "move_focus" "left"}
        ${mkZellijBinding "Ctrl j" "move_focus" "down"}
        ${mkZellijBinding "Ctrl k" "move_focus" "up"}
        ${mkZellijBinding "Ctrl l" "move_focus" "right"}
        ${mkZellijBinding "Alt h" "resize" "left"}
        ${mkZellijBinding "Alt j" "resize" "down"}
        ${mkZellijBinding "Alt k" "resize" "up"}
        ${mkZellijBinding "Alt l" "resize" "right"}
      }
    }
  '';
}
