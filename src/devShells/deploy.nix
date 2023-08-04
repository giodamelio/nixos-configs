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

    config.packages.scripts-z

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
