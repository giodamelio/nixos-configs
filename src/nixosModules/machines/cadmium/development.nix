_: {pkgs, ...}: {
  environment.systemPackages = with pkgs; [
    devenv
    jetbrains.datagrip
    spotify
    aider-chat
  ];
}
