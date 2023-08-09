{
  root,
  debug,
  ...
}: {
  pkgs,
  inputs',
  config,
}:
pkgs.mkShell {
  nativeBuildInputs = [
    config.treefmt.build.wrapper
  ];

  packages = [
    inputs'.deploy-rs.packages.deploy-rs
    inputs'.little_boxes.packages.default

    config.packages.scripts-zz
    config.packages.scripts-deploy-it

    pkgs.lefthook
    pkgs.nurl
    pkgs.just
    pkgs.nushell
  ];

  shellHook = ''
    ${pkgs.lefthook}/bin/lefthook install

    just
  '';
}
