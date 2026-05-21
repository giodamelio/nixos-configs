# Module: gio.niri.binds
#
# Declares the gio.niri.binds option and forwards all binds into
# programs.niri.settings.binds. Safe to import in minimal evalModules
# contexts (e.g. cadmium's single-display config) that lack Home Manager.
#
# For XDG desktop entry generation from labeled binds, also import
# niri-launcher-desktop-entries.nix.
#
# Example usage:
# gio.niri.binds = {
#   "Mod+Backslash".action.set-column-width = "50%";  # no label, not in launcher
#
#   "Mod+Shift+Backslash" = {
#     action.set-column-width = "100%";
#     label = "Column Width 100%";
#     icon = "view-fullscreen";
#   };
#
#   "Mod+H" = {
#     action.focus-column-or-monitor-left = {};
#     label = "Focus Left";
#   };
#
#   "Mod+Return" = {
#     action.spawn = "wezterm";
#     # no label — spawn actions usually don't need launcher entries
#   };
# };
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
