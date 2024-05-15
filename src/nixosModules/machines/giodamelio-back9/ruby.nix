{root, ...}: {pkgs, ...}: let
  aider = root.packages.aider {inherit pkgs;};
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
  ];
}
