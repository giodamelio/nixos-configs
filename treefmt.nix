{
  pkgs,
  evalModule,
  ...
}:
evalModule pkgs {
  projectRootFile = "flake.nix";

  settings.global.excludes = [
    "secrets/**"
    "**/*.toml"
  ];

  programs = {
    # Nix
    alejandra.enable = true;
    # Since we run this after every Edit|Write in Claude Code, deadnix removing stuff was very annoying
    # deadnix.enable = true;
    statix.enable = true;

    # Lua
    stylua.enable = true;
  };
}
