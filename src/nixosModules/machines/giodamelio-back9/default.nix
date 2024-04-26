{super, ...}: _: {
  imports = [
    super.home-manager

    (_: {
      # Allow unfree software
      nixpkgs.config.allowUnfree = true;

      # Enable Nix command and Flakes
      nix = {
        settings = {
          "extra-experimental-features" = ["nix-command" "flakes"];
        };
      };

      # Used for backwards compatibility, please read the changelog before changing.
      # $ darwin-rebuild changelog
      system.stateVersion = 4;

      # Run the Nix Daemon
      services.nix-daemon.enable = true;

      # Make sure we get packages from the right arch
      nixpkgs.hostPlatform = "aarch64-darwin";
    })
  ];
}
