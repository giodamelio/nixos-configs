# software-development — dev tooling for the desktop. Converted from
# nix/modules/nixos/software-development.nix.
#   - `flake.modules.common.nixpkgs-stable` import -> `includes` of the
#     converted nixpkgs-stable aspect (which provides the `pkgsStable` arg).
#   - `perSystem` is a module arg from the per-system aspect; the repo's own
#     packages (Blueprint `flake.packages.<sys>`) are reached as `perSystem.self`.
{den, ...}: {
  den.aspects.software-development = {
    includes = [den.aspects.nixpkgs-stable];
    nixos = {
      perSystem,
      pkgsStable,
      pkgs,
      ...
    }: let
      flakePackages = perSystem.self;
    in {
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
      ];
    };
  };
}
