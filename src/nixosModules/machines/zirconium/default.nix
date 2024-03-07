{
  root,
  inputs,
  homelab,
  super,
  ...
}: _: {
  imports = [
    # Encrypted Secrets
    inputs.ragenix.nixosModules.default

    # Basic packages I want on every system
    root.nixosModules.basic-packages
    root.nixosModules.basic-settings

    # Add server user
    root.nixosModules.users.server

    # Generated hardware config
    super.hardware

    # Setup the Kanidm identity server
    super.kanidm

    # Setup this node as a Nebula lighthouse
    super.nebula

    # Wireguard Mesh Network
    super.headscale

    # Serve DNS records for the Nebula nodes
    super.coredns

    (_: {
      networking.hostId = "54544019";

      # Load the deployment config from our homelab.toml
      inherit (homelab.machines.zirconium) deployment;
    })
  ];
}
