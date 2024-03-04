_: {
  pkgs,
  config,
  ...
}: {
  # Add the Nebula to the system for management
  environment.systemPackages = with pkgs; [nebula qrtool];

  # Setup secrets
  age.secrets.nebula-ca-cert = {
    file = ../../../../secrets/nebula-ca.crt.age;
    owner = "nebula-homelab";
    group = "nebula-homelab";
  };
  age.secrets.nebula-zirconium-cert = {
    file = ../../../../secrets/nebula-zirconium.crt.age;
    owner = "nebula-homelab";
    group = "nebula-homelab";
  };
  age.secrets.nebula-zirconium-key = {
    file = ../../../../secrets/nebula-zirconium.key.age;
    owner = "nebula-homelab";
    group = "nebula-homelab";
  };

  services.nebula.networks.homelab = {
    enable = true;

    isLighthouse = true;
    isRelay = true;

    ca = config.age.secrets.nebula-ca-cert.path;
    cert = config.age.secrets.nebula-zirconium-cert.path;
    key = config.age.secrets.nebula-zirconium-key.path;

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

  # Allow all traffic over the Nebula network
  networking.firewall.trustedInterfaces = ["nebula.homelab"];
}
