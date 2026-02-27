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
    devenv # Development environment manager
    pkgsStable.jetbrains.datagrip # Database IDE from JetBrains
    spotify # Music streaming client
    aider-chat # AI pair programming assistant using OpenAI
    code-cursor # AI code editing assistant using cursor.so
    tokei # Count lines of code easily
    devenv # Easy development environments based on Nix, amazing until I want to stray off the path, which is 90% of the time but really should be 10%
    flakePackages.files_that_change_togather # Little script that uses Git to show which files often get changed in the same commit
    flakePackages.ghclone # Clone GitHub repos into ~/projects/<owner>/<repo>
    zed-editor # New fancy editor. Collaboration first. "Just works" first
    gh # Github CLI

    # Unison lang things
    perSystem.unison-lang.ucm-bin
    perSystem.unison-lang.ucm-desktop
  ];
}
