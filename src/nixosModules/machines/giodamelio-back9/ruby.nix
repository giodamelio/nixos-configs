{root, ...}: {pkgs, ...}: let
  aider = root.packages.aider {inherit pkgs;};
  ecsplorer = root.packages.ecsplorer {inherit pkgs;};
in {
  environment.systemPackages = with pkgs; [
    ruby_3_2
    file
    hurl
    xh
    devenv
    age
    opentofu
    heroku
    aider
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
