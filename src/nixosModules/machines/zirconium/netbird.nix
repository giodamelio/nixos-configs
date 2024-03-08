_: _: {
  services.netbird = {
    enable = true;

    tunnels.main = {};
  };

  services.coredns = {
    enable = true;
    config = ''
      nb.gio.ninja {
        log
        rewrite name suffix .nb.gio.ninja .netbird.cloud answer auto
        forward netbird.cloud 100.121.200.48
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
