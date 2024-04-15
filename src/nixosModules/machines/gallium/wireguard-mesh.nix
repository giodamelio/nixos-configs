_: _: {
  networking.wg-quick.interfaces.wg9 = {
    privateKeyFile = "/var/lib/wg9_private.key";
    listenPort = 34567;

    address = ["10.112.0.3/16"];

    peers = [
      # Zirconium
      {
        publicKey = "YB2jjh7LJZjKYRIMle+LFkK5t1W72OCE39zWSIqSfiY=";
        allowedIPs = ["10.112.0.1/32" "10.111.0.0/16"];
        endpoint = "zirconium.pub.gio.ninja:34567";
        persistentKeepalive = 30;
      }
      # Carbon
      {
        publicKey = "8yTqjUzffR0TJ7VUy0e6Gc3BGWqflpvQr8cvlCbXmEE=";
        allowedIPs = ["10.112.0.2/32"];
        endpoint = "10.0.128.210:34567";
      }
    ];
  };

  networking.firewall = {
    enable = true;
    allowedUDPPorts = [34567];
  };
}
