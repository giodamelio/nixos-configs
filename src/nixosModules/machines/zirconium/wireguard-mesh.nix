_: _: {
  networking.wg-quick.interfaces.wg9 = {
    privateKeyFile = "/var/lib/wg9_private.key";
    listenPort = 34567;

    address = ["10.112.0.1/16"];

    peers = [
      # Carbon
      {
        publicKey = "8yTqjUzffR0TJ7VUy0e6Gc3BGWqflpvQr8cvlCbXmEE=";
        allowedIPs = ["10.112.0.2/32"];
      }
    ];
  };

  networking.firewall = {
    enable = true;
    allowedUDPPorts = [34567];
  };
}
