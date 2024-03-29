{
  root,
  inputs,
  homelab,
  super,
  ...
}: _: {
  imports = [
    # Hardware configs
    super.hardware

    # Encrypted Secrets
    inputs.ragenix.nixosModules.default

    # Basic packages I want on every system
    root.nixosModules.basic-packages
    root.nixosModules.basic-settings

    # Add server user
    root.nixosModules.users.server

    # Security Platform (Identity/Overlay Network)
    super.defguard

    # Wireguard Mesh
    super.wireguard-mesh

    # Monitoring with Grafana/Prometheus/Loki
    super.monitoring

    (_: {
      networking.hostName = "zirconium";
      networking.hostId = "54544019";

      # Load the deployment config from our homelab.toml
      inherit (homelab.machines.zirconium) deployment;
    })
  ];
}
