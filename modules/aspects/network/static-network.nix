{
  lib,
  config,
  ...
}: let
  net = import ./_lib.nix {inherit lib;};
  denHosts = lib.concatMapAttrs (_system: hosts: hosts) config.den.hosts;
in {
  # Routes by host: renders the host's own networking from its facts. Self-gates on
  # mode, so unmanaged hosts (the default) stay untouched. Replaces the legacy
  # homelab/static-network.nix + gio.homelab.networking.
  den.aspects.network.nixos = {
    host,
    lib,
    ...
  }: let
    mode = host.network.mode;
    ifaces = host.network.interfaces;

    # Resolver list = addresses of all static DNS-serving hosts (replaces the
    # hardcoded DNS = [...] the legacy module carried).
    resolvers = net.dnsServerAddresses denHosts;
  in
    lib.mkMerge [
      (lib.mkIf (mode == "static") {
        networking.useNetworkd = true;
        networking.useDHCP = false;
        systemd.network = {
          enable = true;
          networks = lib.mapAttrs' (ifName: ifCfg:
            lib.nameValuePair "10-${ifName}" {
              matchConfig.Name = ifName;
              networkConfig =
                {Address = "${ifCfg.address}/${toString ifCfg.prefixLength}";}
                // lib.optionalAttrs (ifCfg.gateway != null) {Gateway = ifCfg.gateway;}
                // lib.optionalAttrs (resolvers != []) {DNS = resolvers;};
              linkConfig.RequiredForOnline = "routable";
            })
          ifaces;
        };
      })

      (lib.mkIf (mode == "networkmanager") {
        networking.networkmanager.enable = true;
      })

      (lib.mkIf (mode == "dhcp") {
        networking.useNetworkd = true;
        networking.useDHCP = false;
        systemd.network = {
          enable = true;
          networks."10-dhcp" = {
            matchConfig.Name = "en*";
            networkConfig.DHCP = "yes";
            linkConfig.RequiredForOnline = "routable";
          };
        };
      })
      # unmanaged: inert.
    ];
}
