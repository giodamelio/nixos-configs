{
  config,
  lib,
  ...
}: let
  hostname = config.networking.hostName;
  homelabNet = config.gio.homelab.networking;
  hostNet = homelabNet.${hostname} or null;
  allVlans = lib.flatten (lib.mapAttrsToList
    (_ifName: ifCfg: ifCfg.vlans)
    (hostNet.interfaces or {}));

  isolatedVlans = lib.filter (v: v.subnets != []) allVlans;
  isV6 = lib.hasInfix ":";
  mkSet = subs: "{ ${lib.concatStringsSep ", " subs} }";

  # Per-VLAN forward-isolation rules. Drop any packet this host would route
  # *out of* the VLAN (traffic from a device trying to reach the rest of the
  # network), and any packet routed *into* it whose destination is not one of
  # the VLAN's own subnets. Local traffic (e.g. matter-server on this host) uses
  # the input/output path, not forward, so it is unaffected.
  forwardRules = lib.concatMapStringsSep "\n" (v: let
    v4 = lib.filter (s: !isV6 s) v.subnets;
    v6 = lib.filter isV6 v.subnets;
  in
    lib.concatStringsSep "\n" (
      [''iifname "${v.name}" counter drop'']
      ++ lib.optional (v4 != []) ''oifname "${v.name}" ip daddr != ${mkSet v4} counter drop''
      ++ lib.optional (v6 != []) ''oifname "${v.name}" ip6 daddr != ${mkSet v6} counter drop''
    ))
  isolatedVlans;
in {
  config = lib.mkIf (hostNet != null) {
    networking = {
      useNetworkd = true;
      useDHCP = false;

      nftables.tables = lib.mkIf (isolatedVlans != []) {
        vlan-isolation = {
          family = "inet";
          content = ''
            chain forward {
              type filter hook forward priority 0; policy accept;
              ${forwardRules}
            }
          '';
        };
      };
    };

    systemd.network = {
      enable = true;

      netdevs = lib.listToAttrs (map (v:
        lib.nameValuePair "40-${v.name}" {
          netdevConfig = {
            Name = v.name;
            Kind = "vlan";
          };
          vlanConfig.Id = v.id;
        })
      allVlans);

      networks =
        (lib.mapAttrs' (ifName: ifCfg:
          lib.nameValuePair "10-${ifName}" {
            matchConfig.Name = ifName;
            # IPv4 plus an optional static ULA. The GUA still arrives via RA
            # (untouched), so the interface ends up with all three.
            address =
              ["${ifCfg.address}/${toString ifCfg.prefixLength}"]
              ++ lib.optional (ifCfg.ula != null) ifCfg.ula;
            networkConfig = {
              Gateway = ifCfg.gateway;
              DNS = ["10.30.0.10" "10.30.0.11"];
            };
            vlan = map (v: v.name) ifCfg.vlans;
            linkConfig.RequiredForOnline = "routable";
          })
        hostNet.interfaces)
        // (lib.listToAttrs (map (v:
          # VLAN child: take an address but never install a competing default
          # route or DNS — the host's default must stay via the primary interface.
            lib.nameValuePair "40-${v.name}" {
              matchConfig.Name = v.name;
              networkConfig = {
                DHCP = "yes";
                IPv6AcceptRA = true;
              };
              dhcpV4Config = {
                UseGateway = false;
                UseDNS = false;
              };
              ipv6AcceptRAConfig = {
                UseGateway = false;
                UseDNS = false;
              };
              linkConfig.RequiredForOnline = "no";
            })
        allVlans));
    };
  };
}
