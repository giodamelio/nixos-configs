{
  root,
  inputs,
  super,
  homelab,
  ...
}: _: {
  imports = [
    # Disk layout
    super.disko

    # Hardware
    super.hardware

    # Encrypted Secrets
    inputs.ragenix.nixosModules.default

    # Basic packages I want on every system
    root.nixosModules.basic-packages
    root.nixosModules.basic-settings

    # Add server user
    root.nixosModules.users.server

    (_: {
      networking.hostId = "8425e349";

      # Load the deployment config from our homelab.toml
      inherit (homelab.machines.gallium) deployment;
    })
  ];
}
