_: {
  projectRootFile = "flake.nix";

  # Exclude some files from formatting
  settings.excludes = [
    ".envrc"
    "flake.lock"
    ".gitignore"
    "homelab.toml"
  ];

  programs = {
    alejandra.enable = true;
    stylua.enable = true;
  };
}
