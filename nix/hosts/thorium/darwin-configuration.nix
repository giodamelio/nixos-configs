{ config, flake, pkgs, ... }: {
  # Necessary for using flakes on this system.
  nix.settings.experimental-features = "nix-command flakes";

  # Set Git commit hash for darwin-version.
  system.configurationRevision = flake.rev or flake.dirtyRev or null;

  # Setup the users home
  users.users.giodamelio.home = /Users/giodamelio;
  system.primaryUser = "giodamelio";

  # Add ability to used TouchID for sudo authentication
  security.pam.services.sudo_local.touchIdAuth = true;

  # Install some random packages that we need
  environment.systemPackages = with pkgs; [
    gnused
    python312Packages.pgsanity
    postgresql_15
    fblog
    logdy
  ];

  # Setup homebrew
  homebrew = {
    enable = true;
  };

  # Allow keyboard keys to repeat when held down
  system.defaults.NSGlobalDomain.InitialKeyRepeat = 10;
  system.defaults.NSGlobalDomain.KeyRepeat = 1; 

  # Used for backwards compatibility, please read the changelog before changing.
  # $ darwin-rebuild changelog
  system.stateVersion = 6;

  # The platform the configuration will be used on.
  nixpkgs.hostPlatform = "aarch64-darwin";
}
