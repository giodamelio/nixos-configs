{
  inputs,
  pkgs,
  ...
}: let
  inherit (pkgs) lib;
in
  (inputs.nvf.lib.neovimConfiguration {
    inherit pkgs;

    modules = [
      {
        config.vim = {
          lsp.enable = true;
          theme = {
            enable = true;
            name = "tokyonight";
            style = "moon";
          };
          utility.snacks-nvim = {
            enable = true;
            setupOpts = {
              dashboard = {
                pane_gap = 4;
                preset = {
                  keys = [
                    {
                      icon = " ";
                      key = "f";
                      desc = "Find File";
                      action = ":lua Snacks.dashboard.pick('files')";
                    }
                    {
                      icon = " ";
                      key = "n";
                      desc = "New File";
                      action = ":ene | startinsert";
                    }
                    {
                      icon = " ";
                      key = "g";
                      desc = "Find Text";
                      action = ":lua Snacks.dashboard.pick('live_grep')";
                    }
                    {
                      icon = " ";
                      key = "r";
                      desc = "Recent Files";
                      action = ":lua Snacks.dashboard.pick('oldfiles')";
                    }
                    {
                      icon = " ";
                      key = "c";
                      desc = "Config";
                      action = ":lua Snacks.dashboard.pick('files', {cwd = vim.fn.expand('$HOME/nixos-configs/nix/packages/neovim')})";
                    }
                    {
                      icon = " ";
                      key = "s";
                      desc = "Restore Session";
                      section = "session";
                    }
                    {
                      icon = " ";
                      key = "q";
                      desc = "Quit";
                      action = ":qa";
                    }
                  ];
                };
                sections = [
                  {section = "header";}
                  {
                    section = "keys";
                    gap = 1;
                    padding = 1;
                  }
                  {
                    pane = 2;
                    icon = " ";
                    title = "Recent Files";
                    section = "recent_files";
                    indent = 2;
                    padding = 1;
                  }
                  # TODO: enable this if we ever switch over to using the Lazy plugin loader
                  # { pane = 2; title = "Sessions"; section = "sessions"; indent = 2; padding = 1; }
                  {
                    pane = 2;
                    icon = " ";
                    title = "Projects";
                    section = "projects";
                    indent = 2;
                    padding = 1;
                  }
                  {
                    pane = 2;
                    icon = " ";
                    title = "Git Status";
                    section = "terminal";
                    enabled.__raw = "function() return snacks.git.get_root() ~= nil end";
                    cmd = "git status --short --branch --renames";
                    height = 5;
                    padding = 1;
                    ttl = 300;
                    indent = 3;
                  }
                  # TODO: Enable this if we ever switch to Lazy plugin loader (which I want to look into)
                  # { section = "startup"; }
                ];
              };
            };
          };
        };
      }
    ];
  }).neovim
