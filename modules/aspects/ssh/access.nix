{
  lib,
  config,
  ...
}: let
  inherit (import ./_types.nix {inherit lib;}) grantsOf userIdentitiesOf enabledHostsOf;

  domain = "gio.ninja";
  dataDir = ./data;
  userCaPath = dataDir + "/user-ca.pub";
  hasUserCa = builtins.pathExists userCaPath;

  denHosts = enabledHostsOf (lib.concatMapAttrs (_system: hosts: hosts) config.den.hosts);

  userIdentities = builtins.filter (identity: identity.accessTo != {}) (userIdentitiesOf denHosts);

  userGrants = lib.flatten (map grantsOf userIdentities);

  checkGrant = grant:
    if !(denHosts ? ${grant.toHost})
    then throw "ssh-access: grant ${grant.from} -> ${grant.toUser}@${grant.toHost}: unknown host ${grant.toHost}"
    else if grant.toUser != "root" && !((denHosts.${grant.toHost}.users or {}) ? ${grant.toUser})
    then throw "ssh-access: grant ${grant.from} -> ${grant.toUser}@${grant.toHost}: no user ${grant.toUser} on ${grant.toHost}"
    else if grant.publicKey == null
    then throw "ssh-access: ${grant.from} has grants but no ssh.publicKey"
    else grant;

  checkedUserGrants = map checkGrant userGrants;
in {
  den.aspects.ssh-access = {
    nixos = {
      fleet,
      host,
      lib,
      ...
    }: let
      clientGrants = lib.pipe fleet.ssh.externalClients [
        (lib.mapAttrsToList (name: client:
          grantsOf {
            name = "client:${name}";
            inherit (client) publicKey;
            inherit (client) accessTo;
          }))
        lib.flatten
        (map checkGrant)
      ];
      allGrants = checkedUserGrants ++ clientGrants;

      grantsHere = builtins.filter (grant: grant.toHost == host.name) allGrants;
      keysByUser = lib.pipe grantsHere [
        (map (grant: {
          name = grant.toUser;
          value = ["${grant.publicKey} ${grant.from}"];
        }))
        (lib.foldl (acc: kv: acc // {${kv.name} = (acc.${kv.name} or []) ++ kv.value;}) {})
      ];

      userCertsHere = lib.pipe (host.users or {}) [
        builtins.attrNames
        (builtins.filter (userName: builtins.pathExists (dataDir + "/certs/clients/${userName}@${host.name}-cert.pub")))
      ];
    in
      lib.mkIf host.ssh.enable (lib.mkMerge [
        {
          users.users =
            lib.mapAttrs (_user: keys: {openssh.authorizedKeys.keys = keys;})
            keysByUser;

          environment.etc."nix-metadata/ssh-access".text = lib.pipe allGrants [
            (map (grant: "${grant.from} -> ${grant.toUser}@${grant.toHost}"))
            (lib.sort lib.lessThan)
            (lines: lib.concatLines (["# SSH access grants (declared in den; see modules/aspects/ssh/)"] ++ lines))
          ];
        }

        (lib.mkIf hasUserCa {
          services.openssh.settings = {
            TrustedUserCAKeys = "/etc/ssh/user-ca.pub";
            # Cert principals are "<account>@<host>", so an account with no
            # grants has no principals file and cert auth doesn't apply to it.
            AuthorizedPrincipalsFile = "/etc/ssh/authorized-principals/%u";
          };
          environment.etc =
            {
              "ssh/user-ca.pub" = {
                text = builtins.readFile userCaPath;
                mode = "0644";
              };
            }
            // lib.mapAttrs' (userName: _keys:
              lib.nameValuePair "ssh/authorized-principals/${userName}" {
                text = "${userName}@${host.name}\n";
                mode = "0644";
              })
            keysByUser
            // lib.pipe userCertsHere [
              (map (userName:
                lib.nameValuePair "ssh/user-certs/${userName}-cert.pub" {
                  text = builtins.readFile (dataDir + "/certs/clients/${userName}@${host.name}-cert.pub");
                  mode = "0644";
                }))
              lib.listToAttrs
            ];
        })
      ]);

    homeManager = {
      host,
      user,
      lib,
      ...
    }: let
      mine = (lib.findFirst (identity: identity.name == "${user.name}@${host.name}") {accessTo = {};} userIdentities).accessTo;
      grantedUsers = users: builtins.attrNames (lib.filterAttrs (_: granted: granted) users);
      # A matchBlock can pick one user; multi-user grants need `ssh user@host`.
      singleUserTargets = lib.filterAttrs (_toHost: users: builtins.length (grantedUsers users) == 1) mine;
      hasCert = builtins.pathExists (dataDir + "/certs/clients/${user.name}@${host.name}-cert.pub");
    in {
      programs.ssh.matchBlocks =
        lib.mapAttrs' (toHost: users:
          lib.nameValuePair "${toHost}.${domain}" {
            user = builtins.head (grantedUsers users);
          })
        singleUserTargets
        // lib.optionalAttrs hasCert {
          "*.${domain}".certificateFile = "/etc/ssh/user-certs/${user.name}-cert.pub";
        };
    };
  };
}
