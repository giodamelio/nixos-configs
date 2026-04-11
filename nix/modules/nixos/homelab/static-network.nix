{
  config,
  lib,
  ...
}: let
  hostname = config.networking.hostName;
  homelabNet = config.gio.homelab.networking;
  hostNet = homelabNet.${hostname} or null;
in {
  config = lib.mkIf (hostNet != null) {
    networking = {
      useNetworkd = true;
      useDHCP = false;
    };

    systemd.network = {
      enable = true;
      networks = lib.mapAttrs' (ifName: ifCfg:
        lib.nameValuePair "10-${ifName}" {
          matchConfig.Name = ifName;
          networkConfig = {
            Address = "${ifCfg.address}/${toString ifCfg.prefixLength}";
            Gateway = ifCfg.gateway;
            DNS = ["127.0.0.1"];
          };
          linkConfig.RequiredForOnline = "routable";
        })
      hostNet.interfaces;
    };
  };
}
