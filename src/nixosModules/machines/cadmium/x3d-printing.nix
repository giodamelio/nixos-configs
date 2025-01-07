_: {pkgs, ...}: {
  environment.systemPackages = with pkgs; [
    bambu-studio
  ];
}
