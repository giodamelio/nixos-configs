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
