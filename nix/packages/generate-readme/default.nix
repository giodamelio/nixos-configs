{pkgs, ...}:
pkgs.stdenv.mkDerivation {
  name = "generate-readme";

  src = pkgs.lib.fileset.toSource {
    root = ../../..;
    fileset = pkgs.lib.fileset.union ./README.md.tmpl ../../../homelab.toml;
  };
  unpackPhase = "true";

  buildInputs = [pkgs.gomplate];

  buildPhase = ''
    gomplate --file $src/nix/packages/generate-readme/README.md.tmpl --out README.md --datasource homelab=file://$src/homelab.toml
  '';

  installPhase = ''
    mkdir $out/
    cp README.md $out/
  '';
}
