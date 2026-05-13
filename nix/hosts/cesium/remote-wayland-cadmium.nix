{pkgs, ...}: let
  cadmiumNiri = pkgs.writeShellApplication {
    name = "cadmium-niri";
    runtimeInputs = [pkgs.cage pkgs.waypipe];
    text = ''
      export LIBSEAT_BACKEND=logind
      exec cage -D -- waypipe ssh giodamelio@cadmium.gio.ninja \
        niri --config "$HOME/.config/niri/single-display.kdl"
    '';
  };

  desktopFile = pkgs.writeText "cadmium-niri.desktop" ''
    [Desktop Entry]
    Name=Niri (Cadmium)
    Comment=Remote niri session on cadmium via waypipe
    Exec=${cadmiumNiri}/bin/cadmium-niri
    Type=Application
  '';
in {
  services.displayManager.sessionPackages = [
    (pkgs.runCommand "cadmium-niri-session" {
      passthru.providedSessions = ["cadmium-niri"];
    } "mkdir -p $out/share/wayland-sessions && cp ${desktopFile} $out/share/wayland-sessions/cadmium-niri.desktop")
  ];
}
