{root, ...}: {pkgs, ...}: let
  ecsplorer = root.packages.ecsplorer {inherit pkgs;};
in {
  environment.systemPackages = with pkgs; [
    file
    hurl
    xh
    devenv
    age
    opentofu
    heroku
    aider-chat
    zellij
    git-lfs

    # AWS cli
    awscli2
    ssm-session-manager-plugin

    # AWS ECS TUI that allows easy console access
    ecsplorer

    # Quickly click without my mouse
    shortcat

    # Quick easy linux VMs
    lima-bin

    # Language Servers
    yaml-language-server
  ];
}
