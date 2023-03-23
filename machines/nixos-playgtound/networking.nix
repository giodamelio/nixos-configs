{ lib, ... }: {
  # This file was populated at runtime with the networking
  # details gathered from the active system.
  networking = {
    nameservers = [ "8.8.8.8"
 ];
    defaultGateway = "24.199.96.1";
    defaultGateway6 = {
      address = "";
      interface = "eth0";
    };
    dhcpcd.enable = false;
    usePredictableInterfaceNames = lib.mkForce false;
    interfaces = {
      eth0 = {
        ipv4.addresses = [
          { address="24.199.96.183"; prefixLength=20; }
{ address="10.48.0.6"; prefixLength=16; }
        ];
        ipv6.addresses = [
          { address="fe80::9899:3cff:fe5e:dcd6"; prefixLength=64; }
        ];
        ipv4.routes = [ { address = "24.199.96.1"; prefixLength = 32; } ];
        ipv6.routes = [ { address = ""; prefixLength = 128; } ];
      };
      
    };
  };
  services.udev.extraRules = ''
    ATTR{address}=="9a:99:3c:5e:dc:d6", NAME="eth0"
    ATTR{address}=="a6:52:21:67:7a:b5", NAME="eth1"
  '';
}
