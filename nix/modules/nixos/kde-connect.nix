{
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
}
