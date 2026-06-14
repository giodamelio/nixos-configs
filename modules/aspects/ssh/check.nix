{
  lib,
  config,
  ...
}: let
  inherit (import ./_types.nix {inherit lib;}) hostTargetsOf userIdentitiesOf;

  dataDir = config.fleet.ssh.dataDir;
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
  # Every enrolled host/client needs a committed signed cert (run `ssh-ca sync`
  # on the CA host and commit). A failing diff lists the missing files.
  flake.tests.ssh.data-complete = {
    expr = missing;
    expected = [];
  };
}
