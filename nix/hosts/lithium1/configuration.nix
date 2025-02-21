{
  inputs,
  flake,
  ...
}: let
  homelab = builtins.fromTOML (builtins.readFile ../../../homelab.toml);
in {
  imports = [
    inputs.colmena.nixosModules.deploymentOptions
    inputs.ragenix.nixosModules.default

    # Setup hardware
    ./disko.nix
    ./hardware.nix

    flake.nixosModules.basic-packages
    flake.nixosModules.basic-settings
    flake.nixosModules.monitoring

    # Create server user
    ({pkgs, ...}: {
      users.users.server = {
        extraGroups = ["wheel" "docker" "sound"];
        isNormalUser = true;
        shell = pkgs.zsh;
        openssh.authorizedKeys.keys = homelab.ssh_keys;
      };
      security.sudo.wheelNeedsPassword = false;
      programs.zsh.enable = true;
    })

    # Run Headscale for easy networking
    ({
      networking.firewall.allowedTCPPorts = [80 443];

      services.headscale = {
        enable = true;
        address = "0.0.0.0";
        port = 443;

        settings = {
          server_url = "https://headscale.gio.ninja:443";

          tls_letsencrypt_hostname = "headscale.gio.ninja";

          dns = {
            magic_dns = true;
            base_domain = "h.gio.ninja";
          };
        };
      };

      services.tailscale = {
        enable = true;
      };
    })
  ];

  system.stateVersion = "25.05";
}
