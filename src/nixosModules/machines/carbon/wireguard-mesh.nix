_: _: {
  networking.wg-quick.interfaces.wg9 = {
    privateKeyFile = "/var/lib/wg9_private.key";
    listenPort = 34567;

    address = ["10.112.0.2/16"];

    peers = [
      # Zirconium
      {
        publicKey = "YB2jjh7LJZjKYRIMle+LFkK5t1W72OCE39zWSIqSfiY=";
        allowedIPs = ["10.112.0.1/32" "10.111.0.0/16"];
        endpoint = "zirconium.pub.gio.ninja:34567";
        persistentKeepalive = 30;
      }
      # Gallium
      {
        publicKey = "KRiOgigaPraooSECV6+mWQMyOL6y/JGpprQl/rtKTB4=";
        allowedIPs = ["10.112.0.3/32"];
      }
    ];
  };

  networking.firewall = {
    enable = true;
    allowedUDPPorts = [34567];
  };
}
