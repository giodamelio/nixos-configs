{pkgs, ...}:
pkgs.writers.writePython3Bin "waybar-network-monitor" {
  flakeIgnore = ["E501" "E266"];
  makeWrapperArgs = [
    "--prefix"
    "PATH"
    ":"
    (pkgs.lib.makeBinPath [pkgs.iproute2])
  ];
} (builtins.readFile ./network-monitor.py)
