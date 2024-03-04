{root, ...}: {config, ...}: {
  imports = [
    root.nixosModules.services.nebula
  ];

  config = {
    age.secrets.nebula-cadmium-cert = {
      file = ../../../../secrets/nebula-cadmium.crt.age;
      owner = "nebula-homelab";
      group = "nebula-homelab";
    };
    age.secrets.nebula-cadmium-key = {
      file = ../../../../secrets/nebula-cadmium.key.age;
      owner = "nebula-homelab";
      group = "nebula-homelab";
    };

    services.nebula-homelab = {
      enable = true;

      cert = config.age.secrets.nebula-cadmium-cert.path;
      key = config.age.secrets.nebula-cadmium-key.path;
    };
  };
}
