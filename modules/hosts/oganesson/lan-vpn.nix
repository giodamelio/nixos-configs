# oganesson's road-warrior link into the LAN: a client of the UniFi WireGuard
# server. Split tunnel: only the LAN subnets go through it, so the public SSH
# and builder traffic keep using the VNIC. LAN hosts also reach the rest of the
# VCN through it (UniFi routes 10.250.0.0/16 to this peer).
_: let
  iface = "wg-lan";
  credential = "wireguard_lan_private_key";
  unifiPublicKey = "Tm1Mh5hQ3YwHuQeW/4Qpml4kRvCPwBJJup+XmCuMZig=";
  endpoint = "home.gio.ninja:51820";
  lanSubnets = ["10.0.0.0/16" "10.30.0.0/24"];
  vcnSubnet = "10.250.0.0/16";
in {
  den.aspects.oganesson.nixos = {pkgs, ...}: {
    fleet.credentials.needs = [credential];
    systemd.services.systemd-networkd.serviceConfig.LoadCredentialEncrypted = [credential];

    systemd.network.netdevs."50-${iface}" = {
      netdevConfig = {
        Kind = "wireguard";
        Name = iface;
      };
      wireguardConfig.PrivateKey = "@${credential}";
      wireguardPeers = [
        {
          PublicKey = unifiPublicKey;
          Endpoint = endpoint;
          AllowedIPs = lanSubnets;
          # Behind OCI's NAT: keeps the mapping open so the LAN can reach in.
          PersistentKeepalive = 25;
        }
      ];
    };
    systemd.network.networks."50-${iface}" = {
      matchConfig.Name = iface;
      address = ["10.100.0.3/32"];
      routes = map (Destination: {inherit Destination;}) lanSubnets;
      # Split DNS: only the homelab zones go to the LAN resolvers.
      dns = ["10.30.0.10" "10.30.0.11"];
      domains = ["~gio.ninja" "~lan"];
      networkConfig.DNSDefaultRoute = false;
    };
    # The tunnel's own endpoint must not need the tunnel to resolve; resolved
    # sends a name to the link with the most specific matching domain.
    systemd.network.networks."10-dhcp".domains = ["~home.gio.ninja"];

    # networkd resolves the endpoint once; home.gio.ninja is a dynamic address.
    systemd.services.wg-lan-endpoint-refresh = {
      description = "Re-resolve the UniFi WireGuard endpoint";
      after = ["network-online.target"];
      wants = ["network-online.target"];
      serviceConfig.Type = "oneshot";
      script = "${pkgs.wireguard-tools}/bin/wg set ${iface} peer ${unifiPublicKey} endpoint ${endpoint}";
    };
    systemd.timers.wg-lan-endpoint-refresh = {
      wantedBy = ["timers.target"];
      timerConfig = {
        OnBootSec = "5min";
        OnUnitActiveSec = "5min";
      };
    };

    environment.systemPackages = [pkgs.wireguard-tools];

    # LAN -> VCN only, masqueraded so other VCN hosts need no route back to the
    # LAN. Nothing is forwarded the other way except replies.
    boot.kernel.sysctl."net.ipv4.ip_forward" = 1;
    networking.firewall = {
      filterForward = true;
      extraForwardRules = ''
        iifname "${iface}" ip daddr ${vcnSubnet} accept
      '';
    };
    networking.nftables.tables.lan-to-vcn = {
      family = "ip";
      content = ''
        chain postrouting {
          type nat hook postrouting priority srcnat; policy accept;
          iifname "${iface}" ip daddr ${vcnSubnet} masquerade
        }
      '';
    };
  };
}
