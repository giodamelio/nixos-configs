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

    # Run Nebula lighthouse connected to defined.net
    # Use dnclient insead of the open source Nebula package
    # Stolen from: https://gitlab.com/savysound/libraries/nix/dnclient
    ({pkgs, ...}: let
      dnclientPackage = flake.packages.${pkgs.stdenv.system}.dnclient;
    in {
      environment.systemPackages = [dnclientPackage];

      networking.firewall.allowedUDPPorts = [4242];

      systemd.services.dnclient = {
        enable = true;
        description = "Defined Networks' dnclient network configuration tool";
        after = ["network.target"];

        preStart = ''
          mkdir -p /var/lib/defined
        '';

        startLimitIntervalSec = 5;
        serviceConfig = {
          StartLimitBurst = 10;
          Type = "notify";
          NotifyAccess = "main";
          ExecStart = "${dnclientPackage}/bin/dnclient run -config /var/lib/defined -server https://api.defined.net";
          Restart = "always";
          RestartSec = 120;
        };

        wantedBy = ["multi-user.target"];
      };
    })
  ];

  system.stateVersion = "25.05";
}
