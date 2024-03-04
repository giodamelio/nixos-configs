{
  root,
  inputs,
  homelab,
  ...
}:
inputs.nixpkgs.lib.nixosSystem {
  system = "x86_64-linux";

  extraModules = [
    # Not sure why this has to be an extraModule instead of a regular module
    inputs.colmena.nixosModules.deploymentOptions
  ];

  modules = [
    # Encrypted Secrets
    inputs.ragenix.nixosModules.default

    # Hardware
    root.nixosModules.systems.hardware.zirconium

    # Basic packages I want on every system
    root.nixosModules.basic-packages
    root.nixosModules.basic-settings

    # Custom modules
    root.nixosModules.services.lego

    # Add server user
    root.nixosModules.users.server

    # Add Kanidm identity server
    root.nixosModules.services.kanidm

    # Add OpenZiti mesh network
    root.nixosModules.services.ziti

    # Add Nebula mesh network
    root.nixosModules.services.nebula

    ({pkgs, ...}: {
      networking.hostId = "54544019";

      # Load the deployment config from our homelab.toml
      inherit (homelab.machines.zirconium) deployment;

      services.coredns = let
        membersList =
          pkgs.lib.mapAttrsToList
          (host: ip: "${ip}\t${host}.n.gio.ninja")
          homelab.networks.nebula-homelab.members;
        hostsFile = pkgs.writeTextFile {
          name = "coredns-nebula-hosts";
          text = pkgs.lib.concatStringsSep "\n" membersList;
        };
      in {
        enable = true;
        config = ''
          n.gio.ninja {
            hosts ${hostsFile} {
              fallthrough
            }
            forward . 8.8.8.8
          }

          . {
            forward . 8.8.8.8
          }
        '';
      };
    })
  ];
}
