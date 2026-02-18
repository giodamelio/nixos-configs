{pkgs, ...}:
pkgs.writeShellApplication {
  name = "set-terminal-title";
  text = ''
    printf '\033]0;%s\007' "$*"
  '';
}
