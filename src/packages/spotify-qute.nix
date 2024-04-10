_: {pkgs, ...}: let
  script = pkgs.writeShellApplication {
    name = "spotify-qute";
    runtimeInputs = [pkgs.qutebrowser];
    text = ''
      qutebrowser \
        --set "window.title_format" "{perc}qute [spotify]{title_sep}{current_title}" \
        --desktop-file-name "qutebrowser-spotify" \
        --qt-arg "name" "qutebrowser-spotify" \
        https://open.spotify.com
    '';
  };
  desktopItem = pkgs.makeDesktopItem {
    name = "spotify-qute";
    desktopName = "Spotify Qute";
    genericName = "Music Player";
    exec = "${script}/bin/spotify-qute";
    terminal = false;
    icon = "spotify";
    type = "Application";
  };
in
  pkgs.symlinkJoin {
    name = "spotify-qute";
    paths = [script desktopItem];
  }
