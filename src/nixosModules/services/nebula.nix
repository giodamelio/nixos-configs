_: {pkgs, ...}: {
  # Add the Nebula to the system for management
  environment.systemPackages = with pkgs; [nebula qrtool];

  services.nebula.networks.homelab = {
    enable = true;

    isLighthouse = true;
    isRelay = true;

    ca = "/var/lib/nebula/ca.crt";
    cert = "/var/lib/nebula/zirconium.crt";
    key = "/var/lib/nebula/zirconium.key";

    firewall = {
      outbound = [
        {
          host = "any";
          port = "any";
          proto = "any";
        }
      ];
      inbound = [
        {
          host = "any";
          port = "any";
          proto = "any";
        }
      ];
    };
  };
}
