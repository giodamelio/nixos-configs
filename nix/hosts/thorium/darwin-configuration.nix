{
  flake,
  pkgs,
  ...
}: let
  flakePackages = flake.packages.${pkgs.stdenv.system};
in {
  # Necessary for using flakes on this system.
  nix.settings = {
    trusted-users = ["root" "giodamelio"];
    experimental-features = "nix-command flakes";
    extra-experimental-features = "pipe-operators";
  };

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
    devenv # Easy development environments based on Nix, amazing until I want to stray off the path, which is 90% of the time but really should be 10%
    flakePackages.files_that_change_togather # Little script that uses Git to show which files often get changed in the same commit
  ];

  # Setup homebrew
  homebrew = {
    enable = true;
  };

  # Allow keyboard keys to repeat when held down
  system.defaults.NSGlobalDomain = {
    # Values from UI: 120, 90, 60, 30, 12, 6, 2
    KeyRepeat = 2;

    # Values from UI: 120, 94, 68, 35, 25, 15
    InitialKeyRepeat = 15;
  };

  # Used for backwards compatibility, please read the changelog before changing.
  # $ darwin-rebuild changelog
  system.stateVersion = 6;

  # The platform the configuration will be used on.
  nixpkgs.hostPlatform = "aarch64-darwin";
}
