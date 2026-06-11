{
  lib,
  config,
  ...
}: let
  inherit (import ./_types.nix {inherit lib;}) principalsOf hostTargetsOf userIdentitiesOf;

  domain = "gio.ninja";

  denHosts = lib.concatMapAttrs (_system: hosts: hosts) config.den.hosts;

  hostTargets = hostTargetsOf domain denHosts;

  userTargets = lib.pipe (userIdentitiesOf denHosts) [
    (builtins.filter (identity: identity.publicKey != null && identity.accessTo != {}))
    (map (identity: {
      inherit (identity) name;
      value = {
        pubkey = identity.publicKey;
        principals = principalsOf identity;
      };
    }))
    lib.listToAttrs
  ];
in {
  den.aspects.ssh-ca.nixos = {
    fleet,
    perSystem,
    pkgs,
    lib,
    ...
  }: let
    ssh-ca = perSystem.self.ssh-ca;

    externalTargets =
      lib.mapAttrs (name: client: {
        pubkey = client.publicKey;
        principals = principalsOf {
          name = "client:${name}";
          inherit (client) publicKey accessTo;
        };
      })
      fleet.ssh.externalClients;

    targetsJson = pkgs.writeText "ssh-ca-targets.json" (builtins.toJSON {
      hosts = hostTargets;
      clients = userTargets // externalTargets;
    });
  in {
    environment.systemPackages = [ssh-ca];

    systemd.services.ssh-ca-init = {
      description = "Initialize the homelab SSH certificate authority";
      wantedBy = ["multi-user.target"];
      unitConfig.ConditionPathExists = "!/var/lib/ssh-step-ca/config/ca.json";
      serviceConfig = {
        Type = "oneshot";
        # The CA password transits a workdir under /tmp before encryption.
        PrivateTmp = true;
        ExecStart = "${lib.getExe ssh-ca} init";
      };
    };

    systemd.services.ssh-ca-sign = {
      description = "Sign/renew SSH certificates for enrolled hosts and clients";
      after = ["ssh-ca-init.service"];
      serviceConfig = {
        Type = "oneshot";
        PrivateTmp = true;
        LoadCredentialEncrypted = ["ssh-ca-password"];
        ExecStart = "${lib.getExe ssh-ca} sign ${targetsJson}";
      };
    };

    systemd.timers.ssh-ca-sign = {
      description = "Weekly SSH certificate renewal check";
      wantedBy = ["timers.target"];
      timerConfig = {
        OnCalendar = "weekly";
        Persistent = true;
        RandomizedDelaySec = "1h";
      };
    };
  };
}
