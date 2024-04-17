{
  root,
  super,
  homelab,
  ...
}: _: {
  imports = [
    # Disk layout
    super.disko

    # Hardware
    super.hardware

    # Basic packages I want on every system
    root.nixosModules.basic-packages
    root.nixosModules.basic-settings

    # Setup Caddy
    root.nixosModules.core.caddy

    # Wireguard Mesh
    super.wireguard-mesh

    # Expose Monitoring
    root.nixosModules.core.monitoring

    # Add server user
    root.nixosModules.users.server

    # Garage distributed block storage
    super.garage

    (_: {
      networking.hostId = "8425e349";

      # Load the deployment config from our homelab.toml
      inherit (homelab.machines.gallium) deployment;
    })
  ];
}
