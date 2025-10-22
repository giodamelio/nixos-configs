{pkgs, ...}:
pkgs.writeShellApplication {
  name = "git-root";
  runtimeInputs = with pkgs; [git];
  text = ''
    git rev-parse --show-toplevel 2>/dev/null || {
      echo "Not in a git repository" >&2
      exit 1
    }
  '';
}
