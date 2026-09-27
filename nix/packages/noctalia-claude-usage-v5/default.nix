{pkgs, ...}:
pkgs.stdenvNoCC.mkDerivation {
  name = "noctalia-claude-usage-v5";
  src = ./.;
  installPhase = ''
    mkdir -p $out/translations
    cp plugin.toml widget.luau panel.luau $out/
    substitute service.luau $out/service.luau --replace-fail '@nats@' '${pkgs.lib.getExe pkgs.natscli}'
    cp translations/en.json $out/translations/
  '';
}
