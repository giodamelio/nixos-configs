# Raw Home-Manager/evalModules module for niri-launcher-binds. The leading
# underscore keeps import-tree from loading it as a flake-parts module: it is
# imported by ./niri-launcher-binds.nix (the aspect wrapper) and directly by
# minimal `evalModules` contexts (cadmium's single-display niri config) that
# need the gio.niri.binds option without Home Manager.
{
  config,
  lib,
  ...
}: let
  cfg = config.gio.niri.binds;
in {
  options.gio.niri.binds = lib.mkOption {
    type = lib.types.attrsOf (lib.types.submodule {
      options = {
        action = lib.mkOption {
          type = lib.types.anything;
          description = "The Niri action. An attrset with exactly one key (the action name) and its value being the args.";
        };

        label = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          description = "When non-null, a desktop entry is generated with this as the visible name in the launcher.";
        };

        icon = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          description = "XDG icon name for the desktop entry. Only used when label is non-null.";
        };
      };
    });
    default = {};
    description = "Niri keybinds with optional launcher labels.";
  };

  config = lib.mkIf (cfg != {}) {
    programs.niri.settings.binds =
      lib.mapAttrs (_key: entry: {
        inherit (entry) action;
      })
      cfg;
  };
}
