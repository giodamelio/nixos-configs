{
  pkgs,
  self,
  ...
}: let
  myQutebrowser = self.packages.${pkgs.stdenv.system}.qutebrowser-tree-tabs;
in {
  programs.qutebrowser = {
    enable = true;
    # Use totally unrelated package because qutebrowser package is broken on Mac. I am using the brew installed version
    package =
      if pkgs.stdenv.hostPlatform.isLinux
      then myQutebrowser
      else pkgs.git;

    settings = {
      # This doesn't just set the preference...
      colors.webpage.darkmode.enabled = false;
      fonts.default_size = "14pt";
      hints = {
        mode = "letter";
        # padding = mkPadding 3 3 3 3;
        scatter = true;
        uppercase = false;
      };
      tabs = {
        # padding = mkPadding 1 5 5 1;
        position = "right";
        show = "always";

        tree_tabs = true;
      };

      # Edit text with Neovim inside Wezterm
      editor.command = ["wezterm" "start" "--always-new-process" "--" "nvim" "-c" "normal {line}G{column0}l" "{file}"];
    };

    searchEngines = {
      DEFAULT = "https://duckduckgo.com/?q={}";

      # Nix stuff
      nix-home-manager = "https://home-manager-options.extranix.com/?query={}&release=master";
      nix-options = "https://search.nixos.org/options?channel=unstable&type=packages&query={}";
      nix-packages = "https://search.nixos.org/packages?channel=unstable&type=packages&query={}";
    };

    quickmarks = {
      # Back9 Repos
      "github back9 infrastructure" = "https://github.com/back9ins/infrastructure";
      "github back9 boss" = "https://github.com/back9ins/boss";
      "github back9 fairway" = "https://github.com/back9ins/fairway";
      "github back9 conv" = "https://github.com/back9ins/conv";
      "github back9 compulife" = "https://github.com/back9ins/compulife";
      "github back9 actions" = "https://github.com/back9ins/actions";
      "github back9 av" = "https://github.com/back9ins/av";
      "github back9 quote and apply" = "https://github.com/back9ins/quote-and-apply";

      # AWS Console Pages
      "aws ecs" = "https://us-east-1.console.aws.amazon.com/ecs/v2/clusters?region=us-east-1";
      "aws ecr registry" = "https://us-east-1.console.aws.amazon.com/ecr/private-registry/repositories?region=us-east-1";
      "aws rds database" = "https://us-east-1.console.aws.amazon.com/rds/home?region=us-east-1#databases:";
      "aws elasticache redis" = "https://us-east-1.console.aws.amazon.com/elasticache/home?region=us-east-1#/redis";
      "aws secrets manager" = "https://us-east-1.console.aws.amazon.com/secretsmanager/listsecrets?region=us-east-1";
    };
  };

  # Install some dependencies for userscripts
  home.packages = with pkgs; [
    # For qute-bitwarden
    keyutils # To manipulate clipboard
    wofi # For fuzzy selection
  ];
}
