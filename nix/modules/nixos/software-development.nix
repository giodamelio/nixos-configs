{
  flake,
  pkgs,
  pkgsStable,
  ...
}: {
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
    claude-code # AI Coding Agent
  ];
}
