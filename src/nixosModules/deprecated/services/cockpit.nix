_: _: let
  port = 9090;
in {
  services.cockpit = {
    enable = true;
    inherit port;
  };

  # Open up firewall just on the rescue network
  networking.firewall = {
    enable = true;
    interfaces.wg99.allowedTCPPorts = [port];
  };
}
