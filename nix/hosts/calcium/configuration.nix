{
  inputs,
  flake,
  ...
}: let
  homelab = builtins.fromTOML (builtins.readFile ../../../homelab.toml);
in {
  imports = [
    inputs.home-manager.nixosModules.home-manager
    inputs.nixos-wsl.nixosModules.default

    ./hardware.nix

    # Create giodamelio user
    ({pkgs, ...}: {
      users.users.giodamelio = {
        extraGroups = ["wheel"];
        isNormalUser = true;
        shell = pkgs.zsh;
        openssh.authorizedKeys.keys = homelab.ssh_keys;
      };
      programs.zsh.enable = true;
    })

    flake.nixosModules.basic-packages
    flake.nixosModules.basic-settings
    flake.nixosModules.modern-coreutils-replacements

    {
      # Configure WSL
      wsl = {
        enable = true;
        defaultUser = "giodamelio";
      };

      # Allow programs with unfree licences
      nixpkgs.config.allowUnfree = true;

      # Set the system version
      system.stateVersion = "25.05";
    }
  ];
}
