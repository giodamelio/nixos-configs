_: {
  systemd.network.networks."10-lan" = {
    matchConfig.Name = "eno1";
    networkConfig = {
      Address = "10.30.69.191/16";
      Gateway = "10.30.0.1";
      DNS = ["127.0.0.1"];
    };
    linkConfig = {
      RequiredForOnline = "routable";
    };
  };

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
    '';
    interfaces."enp0s20f0u6" = {
      allowedUDPPorts = [67];
    };
  };
}
