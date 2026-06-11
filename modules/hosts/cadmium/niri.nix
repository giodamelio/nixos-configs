# cadmium-niri — giodamelio's niri layout on cadmium: the three-monitor
# layout (was users/giodamelio/niri/three-monitor.nix), the old-keyboard media
# binds, and a pre-rendered single-display config (gaps for the ultrawide-less
# desk) switchable at runtime via ~/.config/niri/single-display.kdl. Converted
# from nix/hosts/cadmium/users/giodamelio/niri.nix.
#
# The single-display KDL is rendered through a minimal evalModules over the
# raw niri settings modules (the `_`-prefixed siblings of the niri aspects),
# exactly as Blueprint did with flake.homeModules.*.
{inputs, ...}: {
  den.aspects.cadmium-niri.homeManager = {
    lib,
    pkgs,
    config,
    ...
  }: let
    inherit (inputs.self.lib.homelab.machines.cadmium) monitor-names;

    singleDisplayConfig =
      inputs.niri.lib.internal.validated-config-for
      pkgs
      config.programs.niri.package
      (lib.evalModules {
        specialArgs = {inherit pkgs;};
        modules = [
          inputs.niri.lib.internal.settings-module
          ../../aspects/desktop/niri/_niri-launcher-binds.nix
          ../../aspects/desktop/niri/_niri-settings.nix
          # was users/giodamelio/niri/single-display.nix
          {programs.niri.settings.layout.gaps = 100;}
        ];
      })
      .config
      .programs
      .niri
      .finalConfig;
  in {
    xdg.configFile."niri/single-display.kdl".source = singleDisplayConfig;

    gio.niri.binds = {
      # My old Microsoft keyboard doesn't have next/prev keys,
      # so I use "My Favorites" buttons labeled 2 and 4.
      # Those are mapped to XF86Launch6 and XF86Launch8 respectivly.
      "XF86Launch8".action.spawn = ["${lib.getExe pkgs.playerctl}" "next"];
      "XF86Launch6".action.spawn = ["${lib.getExe pkgs.playerctl}" "previous"];
    };

    # Three-monitor layout (was users/giodamelio/niri/three-monitor.nix)
    programs.niri.settings = {
      outputs = {
        "${monitor-names.middle}" = {
          scale = 2.0;
          position = {
            x = 1080;
            y = 420;
          };
        };
        "${monitor-names.right}" = {
          scale = 2.0;
          position = {
            x = 3000;
            y = 420;
          };
        };
        "${monitor-names.left}" = {
          scale = 2.0;
          position = {
            x = 0;
            y = 0;
          };
          transform.rotation = 90;
        };
      };
      workspaces = {
        "1" = {open-on-output = monitor-names.middle;};
        "2" = {open-on-output = monitor-names.right;};
        "3" = {open-on-output = monitor-names.left;};
        # Sorts after "1", so the empty workspace "1" stays in front on the middle monitor
        "background" = {open-on-output = monitor-names.middle;};
      };

      spawn-at-startup = [
        {argv = ["thunderbird"];}
        {argv = ["spotify"];}
        {argv = ["io.gitlab.news_flash.NewsFlash"];}
      ];

      # Send the background apps to their workspace without stealing focus
      window-rules = [
        {
          matches = [
            {
              app-id = "thunderbird";
              at-startup = true;
            }
            {
              app-id = "spotify";
              at-startup = true;
            }
            {
              app-id = "io.gitlab.news_flash.NewsFlash";
              at-startup = true;
            }
          ];
          open-on-workspace = "background";
          open-focused = false;
          default-column-width.proportion = 1.0;
        }
      ];
    };
  };
}
