_: {pkgs, ...}: {
  environment.systemPackages = with pkgs; [
    ruby_3_2
    file
    hurl
    xh
  ];
}
