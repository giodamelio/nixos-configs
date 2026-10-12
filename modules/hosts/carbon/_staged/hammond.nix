# hammond — carbon doubles as a small DHCP/NAT router for a private wire on
# enp0s20f0u6 (192.168.100.0/24) and reverse-proxies hammond.gio.ninja to the
# device living on it at .29:4000. The network plumbing stays host-local; the
# vhost + consul become fleet.services (external backend). Converted from
# nix/hosts/carbon/hammond.nix.
_: {
  den.aspects.carbon.nixos = {
    systemd.network.networks."20-hammond" = {
      matchConfig.Name = "enp0s20f0u6";
      networkConfig = {
        Address = "192.168.100.1/24";
        DHCPServer = true;
      };
      dhcpServerConfig = {
        PoolOffset = 10;
        PoolSize = 20;
        DNS = ["192.168.100.1"];
      };
      linkConfig = {
        RequiredForOnline = "no";
      };
    };

    boot.kernel.sysctl = {
      "net.ipv4.ip_forward" = 1;
    };

    networking.nftables.tables.hammond-nat = {
      family = "ip";
      content = ''
        chain postrouting {
          type nat hook postrouting priority srcnat;
          ip saddr 192.168.100.0/24 oifname "eno1" masquerade
        }
      '';
    };

    networking.firewall = {
      filterForward = true;
      extraForwardRules = ''
        iifname "enp0s20f0u6" accept
        oifname "enp0s20f0u6" ct state established,related accept
        iifname "podman0" accept
        oifname "podman0" ct state established,related accept
      '';
      interfaces."enp0s20f0u6" = {
        allowedUDPPorts = [67];
        allowedTCPPorts = [4000];
      };
    };
  };

  # hammond.gio.ninja -> the device at 192.168.100.29:4000 (not a carbon-local
  # service), plus consul registration via the healthcheck.
  den.hosts.x86_64-linux.carbon.services.hammond = {
    endpoint = {
      domain = "hammond";
      backend.host = "192.168.100.29";
      backend.port = 4000;
    };
    healthcheck.target = "https://hammond.gio.ninja/";
  };
}
