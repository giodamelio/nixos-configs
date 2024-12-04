{
  super,
  root,
  ...
}: {lib, ...}: {
  imports = [
    super.home-manager
    super.gui-apps
    # super.ruby
    # super.homebrew

    root.nixosModules.basic-packages
    root.nixosModules.core.modern-coreutils-replacements
    root.nixosModules.services.atuin

    # Keybinding stuff
    (_: {
      system.keyboard = {
        enableKeyMapping = true;
        remapCapsLockToEscape = true;
        swapLeftCtrlAndFn = true;
      };
    })

    (_: {
      # Allow unfree software
      nixpkgs.config.allowUnfree = true;

      # Enable Nix command and Flakes
      nix = {
        settings = {
          extra-experimental-features = ["nix-command" "flakes"];
          extra-nix-path = "nixpkgs=flake:nixpkgs";
          trusted-users = lib.mkAfter [
            "giodamelio"
          ];

          # Add Devenv cachix substituter
          substituters = lib.mkAfter [
            "https://devenv.cachix.org"
          ];
          trusted-public-keys = lib.mkAfter [
            "devenv.cachix.org-1:w1cLUi8dv3hnoSPGAuibQv+f9TZLr6cv/Hm9XgU50cw="
          ];
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
