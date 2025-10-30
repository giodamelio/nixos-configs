{flake, ...}: let
  homelab = builtins.fromTOML (builtins.readFile ../../../homelab.toml);
in {
  imports = [
    # Setup hardware
    ./disko.nix
    ./hardware.nix

    flake.nixosModules.basic-packages
    flake.nixosModules.basic-settings
    flake.nixosModules.onepassword
    flake.nixosModules.lil-scripts

    # Dynamic DNS with Cloudflare
    (
      _: {
        services.cloudflare-dyndns = {
          enable = true;
          # We are overriding the loading to use encrypted credentials
          apiTokenFile = "/noop";
          domains = ["home.gio.ninja"];
          proxied = false;
        };

        # Load the Cloudflare token
        systemd.services.cloudflare-dyndns.serviceConfig = {
          LoadCredential = null;
          LoadCredentialEncrypted = "apiToken:/var/lib/credstore/apiToken";
        };
      }
    )

    # Create server user
    (
      {pkgs, ...}: {
        users.users.server = {
          extraGroups = ["wheel"];
          isNormalUser = true;
          shell = pkgs.zsh;
          openssh.authorizedKeys.keys = homelab.ssh_keys;
        };
        security.sudo.wheelNeedsPassword = false;
        programs.zsh.enable = true;
      }
    )
  ];

  nixpkgs.config.allowUnfree = true;
  system.stateVersion = "25.05";
}
