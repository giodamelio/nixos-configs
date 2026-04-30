{pkgs, ...}:
pkgs.stdenvNoCC.mkDerivation {
  name = "noctalia-claude-usage";
  src = ./.;
  installPhase = ''
    mkdir -p $out
    cp manifest.json BarWidget.qml claude-icon.svg preview.png $out/
  '';
}
