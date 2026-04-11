{
  flake,
  pkgs,
  pkgsStable,
  perSystem,
  ...
}: let
  flakePackages = flake.packages.${pkgs.stdenv.hostPlatform.system};
in {
  imports = [
    flake.modules.common.nixpkgs-stable
  ];

  environment.systemPackages = with pkgs; [
    perSystem.devenv.default # Development environment manager
    pkgsStable.jetbrains.datagrip # Database IDE from JetBrains
    spotify # Music streaming client
    aider-chat # AI pair programming assistant using OpenAI
    code-cursor # AI code editing assistant using cursor.so
    tokei # Count lines of code easily
    flakePackages.files_that_change_togather # Little script that uses Git to show which files often get changed in the same commit
    flakePackages.ghclone # Clone GitHub repos into ~/projects/<owner>/<repo>
    zed-editor # New fancy editor. Collaboration first. "Just works" first
    gh # Github CLI
    perSystem.zmx.default # Terminal multiplexer written in Zig
    perSystem.giopkgs.remind-me-to # CLI reminder tool

    # Unison lang things
    perSystem.unison-lang.ucm-bin
    perSystem.unison-lang.ucm-desktop
  ];
}
