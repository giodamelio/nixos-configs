{pkgs, ...}:
pkgs.writeShellApplication {
  name = "prettypath";
  runtimeInputs = with pkgs; [coreutils];
  text = ''
    echo "$PATH" | tr ':' '\n'
  '';
}
