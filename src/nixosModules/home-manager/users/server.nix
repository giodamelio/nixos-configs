{
  inputs,
  root,
  ...
}: {
  config,
  lib,
  pkgs,
  ...
}: let
  home-manager = inputs.home-manager;
in {
  imports = [
    {
      home-manager.users.server = {
        home.stateVersion = "23.11";

        # Load neovim config from a dedicated package
        xdg.configFile.neovim-config = {
          source = root.packages.neovim-config {inherit pkgs;};
          target = "nvim";
        };

        programs = {
          zsh = {
            enable = true;
            shellAliases = {
              tree = "exa --tree";
            };
          };

          zellij = {
            enable = true;
            settings = {
              pane_frames = false;
              ui.pane_frames.hide_session_name = true;
            };
          };

          exa = {
            enable = true;
            enableAliases = true;
          };

          atuin = {
            enable = true;
            enableZshIntegration = true;
            flags = [
              "--disable-up-arrow"
            ];
          };

          neovim = {
            enable = true;
            defaultEditor = true;
            vimAlias = true;
            viAlias = true;
            withPython3 = true;
            extraPackages = with pkgs; [
              # Language servers
              lua-language-server # Lua
              nil # Nix
            ];
          };
        };
      };
    }
  ];
}
