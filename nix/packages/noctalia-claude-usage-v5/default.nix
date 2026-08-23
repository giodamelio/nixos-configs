{pkgs, ...}:
pkgs.stdenvNoCC.mkDerivation {
  name = "noctalia-claude-usage-v5";
  src = ./.;
  installPhase = ''
    mkdir -p $out/translations
    cp plugin.toml service.luau widget.luau panel.luau $out/
    cp translations/en.json $out/translations/
  '';
}
