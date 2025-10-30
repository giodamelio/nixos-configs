{pkgs, ...}: let
  inherit (pkgs) lib;
in {
  programs.qutebrowser = {
    enable = true;

    settings = {
      # Dark mode by default
      colors.webpage.preferred_color_scheme = "dark";

      fonts.default_size = "14pt";
      hints = {
        mode = "letter";
        # padding = mkPadding 3 3 3 3;
        scatter = true;
        uppercase = false;
      };
      tabs = {
        # padding = mkPadding 1 5 5 1;
        position = "left";
        show = "always";
      };

      # Edit text with Neovim inside Wezterm
      editor.command = ["wezterm" "start" "--always-new-process" "--" "nvim" "-c" "normal {line}G{column0}l" "{file}"];
    };

    # The home manager module can't handle dicts well
    extraConfig = ''
      config.set("content.javascript.log_message.excludes", {
        # See: https://github.com/qutebrowser/qutebrowser/issues/7557
        'userscript:_qute_js': [
          "Uncaught InvalidStateError: Failed to set the 'selectionStart' property on 'HTMLInputElement': The input element's type ('email') does not support selection."
        ]
      })
    '';

    aliases = {
      "1password" = "spawn --userscript 1password";
    };

    keyBindings = {
      normal = {
        "I" = "hint inputs --first";
      };
    };

    searchEngines = {
      DEFAULT = "https://duckduckgo.com/?q={}";

      # Nix stuff
      nix-home-manager = "https://home-manager-options.extranix.com/?query={}&release=master";
      nix-options = "https://search.nixos.org/options?channel=unstable&type=packages&query={}";
      nix-packages = "https://search.nixos.org/packages?channel=unstable&type=packages&query={}";
      noogle = "https://noogle.dev/q?term={}";
    };

    quickmarks = {
      # AWS Console Pages
      "aws ecs" = "https://us-east-1.console.aws.amazon.com/ecs/v2/clusters?region=us-east-1";
      "aws ecr registry" = "https://us-east-1.console.aws.amazon.com/ecr/private-registry/repositories?region=us-east-1";
      "aws rds database" = "https://us-east-1.console.aws.amazon.com/rds/home?region=us-east-1#databases:";
      "aws elasticache redis" = "https://us-east-1.console.aws.amazon.com/elasticache/home?region=us-east-1#/redis";
      "aws secrets manager" = "https://us-east-1.console.aws.amazon.com/secretsmanager/listsecrets?region=us-east-1";
    };
  };

  # Setup some userscripts
  xdg.configFile."qutebrowser/userscripts/1password".source = lib.getExe (pkgs.writeShellApplication {
    name = "qutebrowser-1password";
    runtimeInputs = with pkgs; [python3 jq];
    excludeShellChecks = ["SC2129"];
    text = ./1password.sh;
  });

  # Install some dependencies for userscripts
  home.packages = with pkgs; [
    # For qute-bitwarden
    keyutils # To manipulate clipboard
    wofi # For fuzzy selection
  ];
}
