{pkgs, ...}:
pkgs.writeShellApplication {
  name = "jview";
  runtimeInputs = with pkgs; [less];
  text = builtins.readFile ./jview.sh;
}
