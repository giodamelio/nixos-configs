{inputs, ...}: {
  imports = [
    inputs.microvm.nixosModules.host
  ];

  # Automatically start the VM on boot
  microvm.autostart = ["hammond"];

  ##############################################################################
  # Carbon LAN Bridge (br0)
  #
  # This bridge connects eno1 to the LAN. Future VMs that need direct LAN
  # access can add their tap interfaces to this bridge.
  #
  # Network topology:
  #   LAN <---> eno1 <---> br0 (10.30.69.191) <---> Carbon host
  ##############################################################################

  # Create the LAN bridge device
  systemd.network.netdevs."br0" = {
    netdevConfig = {
      Name = "br0";
      Kind = "bridge";
    };
  };

  # Add eno1 to the LAN bridge (but NOT vm-hammond, that goes to private bridge)
  systemd.network.networks."10-lan-bridge-ports" = {
    matchConfig.Name = ["eno1"];
    networkConfig = {
      Bridge = "br0";
    };
  };

  # Configure the LAN bridge with Carbon's static IP
  systemd.network.networks."10-lan-bridge" = {
    matchConfig.Name = "br0";
    networkConfig = {
      Address = "10.30.69.191/16";
      Gateway = "10.30.0.1";
      DNS = ["127.0.0.1"];
    };
    linkConfig = {
      RequiredForOnline = "routable";
    };
  };

  ##############################################################################
  # Hammond VM Private Network (br-hammond)
  #
  # Hammond lives on a private subnet so we can intercept/MITM its traffic.
  # The host acts as the gateway and NATs traffic to the internet.
  #
  # Network topology:
  #   VM (192.168.100.2) <--tap--> br-hammond (192.168.100.1) <--NAT--> br0 <--> LAN
  #
  # Traffic flow:
  #   - VM -> Internet: Allowed via NAT/masquerade
  #   - VM -> Host: Restricted to specific ports (DNS only by default)
  #   - Host -> VM: Unrestricted
  #   - LAN -> VM: Via Caddy reverse proxy on Carbon
  ##############################################################################

  # Create the private bridge for Hammond
  systemd.network.netdevs."br-hammond" = {
    netdevConfig = {
      Name = "br-hammond";
      Kind = "bridge";
    };
  };

  # Configure the private bridge with the gateway IP
  systemd.network.networks."20-hammond-bridge" = {
    matchConfig.Name = "br-hammond";
    networkConfig = {
      Address = "192.168.100.1/24";
      ConfigureWithoutCarrier = true;
    };
  };

  # Add Hammond's tap interface to the private bridge
  systemd.network.networks."20-hammond-tap" = {
    matchConfig.Name = "vm-hammond";
    networkConfig = {
      Bridge = "br-hammond";
    };
  };

  # Enable IP forwarding for NAT
  boot.kernel.sysctl = {
    "net.ipv4.ip_forward" = 1;
  };

  # NAT for Hammond VM internet access
  networking.nftables.tables.hammond-nat = {
    family = "ip";
    content = ''
      chain postrouting {
        type nat hook postrouting priority srcnat;
        ip saddr 192.168.100.0/24 oifname != "br-hammond" masquerade
      }
    '';
  };

  # Firewall rules for Hammond's private network
  networking.firewall = {
    # Allow specific ports from VM to host
    interfaces."br-hammond" = {
      allowedTCPPorts = [53]; # DNS
      allowedUDPPorts = [53]; # DNS
    };

    # Allow forwarding for NAT
    filterForward = true;
    extraForwardRules = ''
      iifname "br-hammond" accept
      oifname "br-hammond" ct state established,related accept
    '';
  };

  # Reverse proxy to expose Hammond web UI to the LAN
  # LAN users access hammond.gio.ninja -> Caddy -> 192.168.100.2:4000
  services.gio.reverse-proxy = {
    enable = true;
    virtualHosts = {
      "hammond" = {
        host = "192.168.100.2";
        port = 4000;
      };
    };
  };
}
