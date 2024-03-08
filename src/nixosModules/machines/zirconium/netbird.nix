_: {pkgs, ...}: {
  environment.systemPackages = [pkgs.dogdns];

  services.netbird = {
    enable = true;

    tunnels.main = {};
  };

  services.coredns = {
    enable = true;
    config = ''
      n.gio.ninja {
        log
        rewrite name suffix .n.gio.ninja .netbird.cloud answer auto
        forward netbird.cloud 100.121.152.171
      }

      . {
        forward . 8.8.8.8
      }
    '';
  };

  # Open up firewall port for CoreDNS
  networking.firewall = {
    enable = true;
    allowedUDPPorts = [53];
  };
}
