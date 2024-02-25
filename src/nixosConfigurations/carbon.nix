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
    # Disk layout
    inputs.disko.nixosModules.disko
    root.disko.systems.carbon

    # Boot with systemd-boot
    root.nixosModules.core.bootloader-systemd-boot
    root.nixosModules.core.bootloader-zfs

    # Basic packages I want on every system
    root.nixosModules.basic-packages
    root.nixosModules.basic-settings

    # Autosnapshot with Sanoid
    root.nixosModules.services.sanoid
    (_: {
      gio.services.zfs_backup = {
        enable = true;
        datasets = [
          "tank/home"
          "tank/nix"
          "tank/root"
        ];
      };
    })

    # Add server user
    root.nixosModules.users.server

    ({pkgs, ...}: {
      networking.hostId = "3a06cc0b";

      # Load the deployment config from our homelab.toml
      deployment = homelab.machines.carbon.deployment;

      # Setup a PostgreSQL db
      environment.systemPackages = [pkgs.pgcli];
      services.postgresql = {
        enable = true;

        ensureDatabases = ["damelio_prod"];
        ensureUsers = [
          {
            name = "damelio_prod";
            ensureDBOwnership = true;
            ensureClauses.login = true;
          }
        ];

        authentication = ''
          # Trust all local connections to the Unix socket
          local all all trust

          # Trust server to connect from localhost
          host all server samehost trust
        '';
      };
    })
  ];
}
