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
    extraCommands = ''
      iptables -A FORWARD -i wg9 -o wg0 -j ACCEPT
      iptables -A FORWARD -i wg0 -o wg9 -j ACCEPT
    '';
  };

  # Forward traffic over IPv4 and IPv^
  boot.kernel.sysctl = {
    "net.ipv4.conf.all.forwarding" = true;
    "net.ipv6.conf.all.forwarding" = true;
  };
}
