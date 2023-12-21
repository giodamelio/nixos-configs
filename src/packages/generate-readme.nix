{
  inputs,
  debug,
  ...
}: {pkgs}: let
  lib = pkgs.lib;
  machineListItems = lib.attrsets.mapAttrsToList (name: value: "${name}=${value}");
in pkgs.stdenv.mkDerivation {
  name = "generate-readme";

  src = lib.fileset.toSource {
    root = ../..;
    fileset = lib.fileset.union ./README.md.tmpl ../../homelab.toml;
  };
  unpackPhase = "true";

  buildInputs = [ pkgs.gomplate ];

  buildPhase = ''
    gomplate --file $src/src/packages/README.md.tmpl --out README.md --datasource homelab=file://$src/homelab.toml
  '';

  installPhase = ''
    mkdir $out/
    cp README.md $out/
  '';
}
