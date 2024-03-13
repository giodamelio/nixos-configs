_: _: {
  networking.wg-quick.interfaces.wg9 = {
    privateKeyFile = "/var/lib/wg9_private.key";
    listenPort = 34567;

    address = ["10.112.0.2/16"];

    peers = [
      # Zirconium
      {
        publicKey = "YB2jjh7LJZjKYRIMle+LFkK5t1W72OCE39zWSIqSfiY=";
        allowedIPs = ["10.112.0.1/32"];
        endpoint = "zirconium.gio.ninja:34567";
        persistentKeepalive = 30;
      }
    ];
  };

  networking.firewall = {
    enable = true;
    allowedUDPPorts = [34567];
  };
}
