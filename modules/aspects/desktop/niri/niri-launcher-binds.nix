# niri-launcher-binds — declares gio.niri.binds and forwards them into
# programs.niri.settings.binds. Converted from
# nix/modules/home/niri-launcher-binds.nix.
#
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
_: {
  den.aspects.niri-launcher-binds.homeManager = import ./_niri-launcher-binds.nix;
}
