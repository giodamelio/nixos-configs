{ lib, ... }: {
  # This file was populated at runtime with the networking
  # details gathered from the active system.
  networking = {
    nameservers = [ "8.8.8.8"
 ];
    defaultGateway = "143.110.144.1";
    defaultGateway6 = {
      address = "2604:a880:4:1d0::1";
      interface = "eth0";
    };
    dhcpcd.enable = false;
    usePredictableInterfaceNames = lib.mkForce false;
    interfaces = {
      eth0 = {
        ipv4.addresses = [
          { address="143.110.154.12"; prefixLength=20; }
{ address="10.48.0.6"; prefixLength=16; }
        ];
        ipv6.addresses = [
          { address="2604:a880:4:1d0::5e9:7000"; prefixLength=64; }
{ address="fe80::3c8a:8dff:fe4f:dbb2"; prefixLength=64; }
        ];
        ipv4.routes = [ { address = "143.110.144.1"; prefixLength = 32; } ];
        ipv6.routes = [ { address = "2604:a880:4:1d0::1"; prefixLength = 128; } ];
      };
      
    };
  };
  services.udev.extraRules = ''
    ATTR{address}=="3e:8a:8d:4f:db:b2", NAME="eth0"
    ATTR{address}=="6e:34:33:a3:47:46", NAME="eth1"
  '';
}
