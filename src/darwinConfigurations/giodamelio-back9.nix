{ root, inputs, ... }: inputs.nix-darwin.lib.darwinSystem {
  modules = [
    ({ pkgs, ... }: {
      environment.systemPackages = [
        pkgs.git
        (root.packages.neovim { inherit pkgs; })
      ];

      # This is very important to get it all working
      programs.zsh.enable = true;

      # Allow unfree software
      nixpkgs.config.allowUnfree = true;

      nix = {
        settings = {
          "extra-experimental-features" = [ "nix-command" "flakes" ];
        };
      };

      # Used for backwards compatibility, please read the changelog before changing.
      # $ darwin-rebuild changelog
      system.stateVersion = 4;

      services.nix-daemon.enable = true;
      nixpkgs.hostPlatform = "aarch64-darwin";
    })
  ];
  specialArgs = {};
}
