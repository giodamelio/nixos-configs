{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.gio.nix-activate-config;

  # Map system types to their respective nh commands
  systemCommands = {
    nixos = "nh os switch .";
    darwin = "nh darwin switch .";
    home = "nh home switch .";
  };

  # Determine the final command to use based on which option is set
  finalCommand =
    if cfg.activation ? system
    then systemCommands.${cfg.activation.system}
    else cfg.activation.command;
in {
  options.gio.nix-activate-config = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Whether to enable the nix-activate-config script. Defaults to true for all systems.";
    };

    activation = lib.mkOption {
      type = lib.types.oneOf [
        (lib.types.submodule {
          options = {
            system = lib.mkOption {
              type = lib.types.enum ["nixos" "darwin" "home"];
              description = "The type of system to activate. Use this for standard nh commands.";
              example = "darwin";
            };
          };
        })
        (lib.types.submodule {
          options = {
            command = lib.mkOption {
              type = lib.types.str;
              description = "Custom command to run to activate the Nix configuration. Use this for non-standard activation commands.";
              example = "sudo nixos-rebuild switch --flake .";
            };
          };
        })
      ];
      description = "Configuration for the nix-activate-config script. Either specify a system type for standard nh commands, or provide a custom command.";
    };
  };

  config = lib.mkIf cfg.enable {
    home.packages = [
      (pkgs.writeShellScriptBin "nix-activate-config" ''
        set -e
        cd "$HOME/nixos-configs"
        echo "Activating Nix configuration..."
        ${finalCommand}
      '')
    ];
  };
}
