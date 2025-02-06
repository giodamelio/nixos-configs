{
  pkgs,
  lib,
  ...
}:
pkgs.stdenv.mkDerivation {
  name = "generate-readme";

  src = lib.fileset.toSource {
    root = ../../..;
    fileset = lib.fileset.union ./README.md.tmpl ../../../homelab.toml;
  };
  unpackPhase = "true";

  buildInputs = [pkgs.gomplate];

  buildPhase = ''
    gomplate --file $src/src/pkgs-by-name/generate-readme/README.md.tmpl --out README.md --datasource homelab=file://$src/homelab.toml
  '';

  installPhase = ''
    mkdir $out/
    cp README.md $out/
  '';
}
