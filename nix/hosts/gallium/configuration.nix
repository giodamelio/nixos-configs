{flake, ...}: let
  homelab = builtins.fromTOML (builtins.readFile ../../../homelab.toml);
in {
  imports = [
    # Setup hardware
    ./filesystems.nix
    ./hardware.nix

    flake.nixosModules.basic-packages
    flake.nixosModules.basic-settings
    flake.nixosModules.credential
    flake.nixosModules.onepassword
    flake.nixosModules.lil-scripts
    flake.nixosModules.send-metrics
    flake.nixosModules.reverse-proxy

    ./postgresql.nix # Shared PostgreSQL database
    ./immich.nix # Photo/Video backup service
    ./garage.nix # Open Source distributed object storage (S3 compatable)

    # Add some helpful programs
    (
      {pkgs, ...}: {
        environment.systemPackages = with pkgs; [
          dua
          dust
          parted
        ];
      }
    )

    # Create server user
    (
      {pkgs, ...}: {
        users.users.server = {
          extraGroups = [
            "wheel"
            "docker"
            "sound"
          ];
          isNormalUser = true;
          shell = pkgs.zsh;
          openssh.authorizedKeys.keys = homelab.ssh_keys;
        };
        security.sudo.wheelNeedsPassword = false;
        programs.zsh.enable = true;
      }
    )

    (_: {
      networking.hostId = "8425e349";

      nixpkgs.config.allowUnfree = true;

      system.stateVersion = "25.11";
    })
  ];
}
