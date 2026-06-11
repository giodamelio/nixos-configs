_: {
  perSystem = {pkgs, ...}: let
    herdr-proxy = pkgs.writers.writePython3Bin "herdr-proxy" {
      libraries = [];
    } (builtins.readFile ./herdr-proxy.py);
  in {
    packages.herdr-proxy = herdr-proxy;
  };
}
