_: {config, ...}: {
  services.prometheus = {
    exporters = {
      node = {
        enable = true;
        enabledCollectors = ["systemd"];
        listenAddress = "0.0.0.0";
      };
    };
  };

  networking.firewall.interfaces."wg9" = {
    allowedTCPPorts = [
      config.services.prometheus.exporters.node.port
    ];
  };
}
