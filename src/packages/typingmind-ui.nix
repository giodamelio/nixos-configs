_: {pkgs, ...}: let
  script = pkgs.writeShellApplication {
    name = "typingmind-ui";
    runtimeInputs = [pkgs.qutebrowser];
    text = ''
      qutebrowser \
        --set "window.title_format" "TypingMind" \
        --desktop-file-name "typingmind" \
        --qt-arg "name" "typingmind-ui" \
        https://www.typingmind.com
    '';
  };
  desktopItem = pkgs.makeDesktopItem {
    name = "typingmind";
    desktopName = "TypingMind";
    exec = "${script}/bin/typingmind-ui";
    terminal = false;
    type = "Application";
  };
in
  pkgs.symlinkJoin {
    name = "typingmind-ui";
    paths = [script desktopItem];
  }
