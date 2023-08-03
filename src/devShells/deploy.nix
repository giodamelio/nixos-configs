{
  pkgs,
  inputs',
  config,
  ...
}:
pkgs.mkShell {
  nativeBuildInputs = [
    config.treefmt.build.wrapper
  ];

  packages = [
    inputs'.deploy-rs.packages.deploy-rs

    pkgs.lefthook
    pkgs.nurl
  ];

  shellHook = ''
    ${pkgs.lefthook}/bin/lefthook install
  '';
}
