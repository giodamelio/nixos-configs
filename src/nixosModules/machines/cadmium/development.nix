_: {pkgs, ...}: {
  environment.systemPackages = with pkgs; [
    devenv                  # Development environment manager
    jetbrains.datagrip    # Database IDE from JetBrains
    spotify                 # Music streaming client
    aider-chat             # AI pair programming assistant using OpenAI
    code-cursor            # AI code editing assistant using cursor.so
  ];
}
