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
  scripts = root.packages.scripts {inherit pkgs;};
in {
  imports = [
    root.nixosModules.home-manager-loader
    {
      home-manager.users.giodamelio = {
        home.stateVersion = "23.11";

        # Load neovim config from a dedicated package
        xdg.configFile.neovim-config = {
          source = root.packages.neovim-config {inherit pkgs;};
          target = "nvim";
        };

        home.packages = [
          scripts.zz
        ];

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

          git = {
            enable = true;
            delta.enable = true;
            ignores = [
              "tmp/"
              ".direnv/"
            ];
          };

          zoxide = {
            enable = true;
            enableZshIntegration = true;
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

          starship = {
            enable = true;
            settings = {
              format = "$all$fill $time\n$character";
              directory = {
                truncation_length = 4;
              };
              fill = {
                symbol = ".";
                style = "#666666";
              };
              time = {
                disabled = false;
              };
              line_break = {
                disabled = true;
              };
            };
          };

          nnn = {
            enable = true;
          };

          nix-index.enable = true;
        };

        # TODO: contribute this back to the HomeManager module
        # https://github.com/nix-community/home-manager/blob/master/modules/programs/nix-index.nix
        # Example: https://github.com/nix-community/home-manager/blob/6a20e40acaebf067da682661aa67da8b36812606/modules/services/borgmatic.nix#L45
        systemd.user.services.nix-index-update = {
          Unit = {
            Description = "Update the nix-index index";

            # Prevent index update unless computer is plugged into the wall
            ConditionACPower = true;
          };

          Service = {
            Type = "oneshot";
            ExecStart = "${pkgs.nix-index}/bin/nix-index";

            # Lower CPU and I/O priority:
            Nice = 19;
            CPUSchedulingPolicy = "batch";
            IOSchedulingClass = "best-effort";
            IOSchedulingPriority = 7;
            IOWeight = 100;
          };

          Install = {
            WantedBy = ["default.target"];
          };
        };
        systemd.user.timers.nix-index-update = {
          Unit.Description = "Update the nix-index index";
          Timer = {
            OnCalendar = "daily";
            Persistent = true;
            RandomizedDelaySec = "10m";
          };
          Install.WantedBy = ["timers.target"];
        };
      };
    }
  ];
}
