{
  lib,
  config,
  ...
}: let
  inherit (import ./_types.nix {inherit lib;}) hostTargetsOf userIdentitiesOf;

  dataDir = ./data;
  denHosts = lib.concatMapAttrs (_system: hosts: hosts) config.den.hosts;

  enrolledHosts = builtins.attrNames (hostTargetsOf "gio.ninja" denHosts);
  certClients = lib.pipe (userIdentitiesOf denHosts) [
    (builtins.filter (identity: identity.publicKey != null && identity.accessTo != {}))
    (map (identity: identity.name))
  ];
  externalClients = builtins.attrNames config.fleet.ssh.externalClients;

  expected =
    lib.optionals (enrolledHosts != [] || certClients != [] || externalClients != []) [
      "host-ca.pub"
      "user-ca.pub"
    ]
    ++ map (name: "certs/${name}-cert.pub") enrolledHosts
    ++ map (name: "certs/clients/${name}-cert.pub") (certClients ++ externalClients);

  missing = builtins.filter (file: !(builtins.pathExists (dataDir + "/${file}"))) expected;
in {
  perSystem = {pkgs, ...}: {
    checks.ssh-data-complete = pkgs.runCommand "ssh-data-complete" {inherit missing;} ''
      if [ -n "$missing" ]; then
        echo "missing files under modules/aspects/ssh/data/ (run \`ssh-ca sync\` on the CA host and commit):"
        for f in $missing; do echo "  $f"; done
        exit 1
      fi
      echo ok > $out
    '';
  };
}
