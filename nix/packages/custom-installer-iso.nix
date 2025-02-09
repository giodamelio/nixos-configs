{inputs, flake, pkgs, ...}: let
  customNeovim = flake.packages.${pkgs.stdenv.system}.neovim;
  homelab = builtins.fromTOML (builtins.readFile ../../homelab.toml);
in inputs.nixos-generators.nixosGenerate {
  system = "x86_64-linux";
  modules = [
    (_: {
      # Add my custom Neovim
      environment.systemPackages = [
        customNeovim
      ];

      # Enable flakes
      nix.settings.experimental-features = ["nix-command" "flakes"];

      # This enables some drivers that all-hardware.nix doesn't
      virtualisation.hypervGuest.enable = true;

      # Print the ip address at shell entrance
      environment.etc."issue.d/00-ip.issue".text = "IP Address: \\4\n\n";

      # Enable ssh and set keys for both users
      users.users.root = {
        openssh.authorizedKeys.keys = homelab.ssh_keys;
      };
      users.users.nixos = {
        openssh.authorizedKeys.keys = homelab.ssh_keys;
      };

      system.stateVersion = "25.05";
    })
  ];
  format = "install-iso";
}
