{pkgs, ...}: {
  environment.systemPackages = with pkgs; [
    signal-cli
    signal-desktop
  ];
}
