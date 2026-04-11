{
  flake,
  lib,
  ...
}: {
  # Import all required Home Manager modules that should be available on every system
  imports = [
    flake.homeModules.nix-activate
  ];

  options.gio.role = lib.mkOption {
    type = lib.types.enum ["server" "desktop"];
    description = "The role of the computer";
  };
}
