{
  lib,
  config,
  ...
}: let
  inherit (import ./_types.nix {inherit lib;}) enabledHosts mountsList;
  net = import ../network/_lib.nix {inherit lib;};
  denHosts = lib.concatMapAttrs (_system: hosts: hosts) config.den.hosts;
  enabled = enabledHosts denHosts;

  # Verify every enabled mount references real, nfs-enabled den hosts on both
  # sides — caught here rather than as an opaque "attribute missing" deep in the
  # render. Exports and mounts are addressed by IP, so each side also needs
  # exactly one static address.
  checkSide = mountName: side: host:
    if !(denHosts ? ${host})
    then ["nfs mount ${mountName}: ${side} host '${host}' is not a den host"]
    else if !(enabled ? ${host})
    then ["nfs mount ${mountName}: ${side} host '${host}' has nfs.enable = false"]
    else if lib.length (net.interfacesOf denHosts.${host}) != 1
    then ["nfs mount ${mountName}: ${side} host '${host}' needs exactly one static network interface"]
    else [];

  errors = lib.pipe (mountsList config.fleet.nfs.mounts) [
    (map (m: checkSide m.name "server" m.server.host ++ checkSide m.name "client" m.client.host))
    lib.flatten
    (lib.concatStringsSep "\n")
  ];
in {
  perSystem = {pkgs, ...}: {
    checks.fleet-nfs-mounts-valid = pkgs.runCommand "fleet-nfs-mounts-valid" {inherit errors;} ''
      if [ -n "$errors" ]; then
        echo "invalid fleet.nfs.mounts:"
        printf '  %s\n' "$errors"
        exit 1
      fi
      echo ok > $out
    '';
  };
}
