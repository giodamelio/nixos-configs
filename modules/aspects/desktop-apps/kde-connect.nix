# kde-connect — folded dual-class aspect (the original goal of the migration:
# one feature, both classes, one file).
#   - nixos half (was nix/modules/nixos/kde-connect.nix): opens the KDE Connect
#     firewall ports, but only when an HM user on the host enabled the service.
#   - homeManager half (was nix/modules/home/kde-connect.nix): the kdeconnect
#     service + SFTP deps + the optional Noctalia plugin.
_: {
  den.aspects.kde-connect = {
    nixos = {
      config,
      lib,
      ...
    }: let
      # Check if any Home Manager user has KDE Connect enabled
      hmUsers = config.home-manager.users or {};
      anyUserHasKdeConnect = lib.any (
        userCfg: userCfg.services.kdeconnect.enable or false
      ) (lib.attrValues hmUsers);
    in {
      networking.firewall = lib.mkIf anyUserHasKdeConnect {
        allowedTCPPortRanges = [
          {
            from = 1714;
            to = 1764;
          }
        ];
        allowedUDPPortRanges = [
          {
            from = 1714;
            to = 1764;
          }
        ];
      };
    };

    homeManager = {
      config,
      lib,
      pkgs,
      ...
    }: {
      services.kdeconnect = {
        enable = true;
        indicator = true;
      };

      # File browsing dependencies for KDE Connect's SFTP feature
      home.packages = with pkgs; [
        sshfs
        fuse
      ];

      # When noctalia is enabled, add the KDE Connect plugin
      programs.noctalia-shell.plugins = lib.mkIf config.programs.noctalia-shell.enable {
        states = {
          kde-connect = {
            enabled = true;
            sourceUrl = "https://github.com/noctalia-dev/noctalia-plugins";
          };
        };
      };
    };
  };
}
