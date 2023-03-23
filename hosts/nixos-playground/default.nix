{ nixpkgs, ... }: {
  imports = [
    ./hardware-configuration.nix
    ./networking.nix # generated at runtime by nixos-infect
    ../../common/base-packages.nix
    ../../common/users/giodamelio.nix
  ];

  boot.cleanTmpDir = true;
  zramSwap.enable = true;
  networking.hostName = "nixos-playground";
  networking.domain = "";
  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "no";
      PasswordAuthentication = false;
    };
  };

  users.users.root.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFbUQ/gUuzZbOtBPseVWL1GVrjP08JqdNwHdndQgH+Am giodamelio@penguin" 
  ];

  # TODO: figure out how to make this work again
  # nix.registry.nixpkgs.flake = nixpkgs;

  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  system.stateVersion = "22.05";
}
