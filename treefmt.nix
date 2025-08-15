{
  projectRootFile = "flake.nix";

  settings.global.excludes = [
    "secrets/**"
    "**/*.toml"
  ];

  programs = {
    # Nix
    alejandra.enable = true;
    deadnix.enable = true;
    statix.enable = true;

    # Lua
    stylua.enable = true;
  };
}
