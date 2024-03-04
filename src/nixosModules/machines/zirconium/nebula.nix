{root, ...}: {config, ...}: {
  imports = [
    root.nixosModules.services.nebula
  ];

  config = {
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

    services.nebula-homelab = {
      enable = true;

      cert = config.age.secrets.nebula-zirconium-cert.path;
      key = config.age.secrets.nebula-zirconium-key.path;

      isLighthouse = true;
      isRelay = true;
    };
  };
}
