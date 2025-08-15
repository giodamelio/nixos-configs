{flake, ...}: {
  # Import all required Home Manager modules that should be available on every system
  imports = [
    flake.homeModules.nix-activate
  ];
}
