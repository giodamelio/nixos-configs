_: _: {
  # Collect and store metrics
  services.prometheus = {
    exporters = {
      node = {
        enable = true;
        enabledCollectors = [
          "systemd"
        ];
      };
    };
  };

  # Allow traffic from within the Netbird network
  networking.firewall.interfaces.wt0.allowedTCPPorts = [
    9100 # Node Exporter
  ];
}
