{lib}: rec {
  accessToType = lib.types.attrsOf (lib.types.attrsOf lib.types.bool);

  identityOptions = {
    publicKey = lib.mkOption {
      type = lib.types.singleLineStr;
      description = "ed25519 public key of this identity.";
    };
    accessTo = lib.mkOption {
      type = accessToType;
      default = {};
      description = "Access grants: accessTo.<toHost>.<toUser> = true.";
    };
  };

  # accessTo -> [{ from, publicKey, toHost, toUser }]
  grantsOf = identity:
    lib.pipe identity.accessTo [
      (lib.mapAttrsToList (toHost: users:
        lib.mapAttrsToList (toUser: granted:
          lib.optional granted {
            from = identity.name;
            inherit (identity) publicKey;
            inherit toHost toUser;
          })
        users))
      lib.flatten
    ];

  principalsOf = identity: map (grant: "${grant.toUser}@${grant.toHost}") (grantsOf identity);

  # enable is checked before any other ssh fact so a disabled host's hostKey
  # (required, no default) is never read.
  enabledHostsOf = lib.filterAttrs (_name: host: host.ssh.enable);

  hostTargetsOf = domain: denHosts:
    lib.pipe denHosts [
      enabledHostsOf
      (lib.filterAttrs (_name: host: host.ssh.hostKey != null))
      (lib.mapAttrs (name: host: {
        pubkey = host.ssh.hostKey;
        principals = [name "${name}.${domain}"] ++ host.ssh.extraPrincipals;
      }))
    ];

  userIdentitiesOf = denHosts:
    lib.pipe denHosts [
      enabledHostsOf
      (lib.mapAttrsToList (hostName: host:
        lib.mapAttrsToList (userName: user: {
          name = "${userName}@${hostName}";
          publicKey = user.ssh.publicKey;
          accessTo = user.ssh.accessTo;
        }) (host.users or {})))
      lib.flatten
    ];
}
