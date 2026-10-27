# zfs-backup — sanoid autosnapshots behind the gio.zfs_backup options, plus
# syncoid replication of each host's fleet.backups.zfs datasets to gallium.
# Converted from nix/modules/nixos/zfs-backup.nix.
_: {
  den.aspects.zfs-backup.nixos = {
    lib,
    config,
    fleet,
    host,
    pkgs,
    ...
  }: let
    cfg = config.gio.zfs_backup;
    zfs = "${config.boot.zfs.package}/bin/zfs";
    recvRoot = "tank/backups";
    replicated = fleet.backups.zfs.${host.name} or [];
    # Same escaping as nixos/modules/services/backup/syncoid.nix, so the names
    # line up with its syncoid-<name> units.
    escapeUnitName = name:
      lib.concatMapStrings (s:
        if lib.isList s
        then "-"
        else s) (builtins.split "[^a-zA-Z0-9_.\\-]+" name);
    initialMarker = dataset: "/var/lib/syncoid/initial-${escapeUnitName dataset}.done";
  in {
    options.gio.zfs_backup = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = ''
          Small module to allow easy auto creation/pushing of ZFS snapshots
        '';
      };

      makeRecvUser = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = ''
          Make a user to recieve the syncs
        '';
      };

      datasets = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [];
        description = ''
          List of datasets to snapshot locally (replicated ones come from
          fleet.backups.zfs)
        '';
      };
    };

    config = let
      default_schedule = {
        hourly = 48;
        daily = 32;
        monthly = 8;
        yearly = 8;

        autosnap = true;
        autoprune = true;
      };
    in
      lib.mkMerge [
        {
          services.sanoid = lib.mkIf (cfg.enable || replicated != []) {
            enable = true;

            datasets =
              lib.attrsets.genAttrs (cfg.datasets ++ replicated) (_: default_schedule)
              # Received snapshots carry sanoid's names, so sanoid prunes them here
              # on the sender's schedule; it never takes its own.
              // lib.optionalAttrs cfg.makeRecvUser {
                ${recvRoot} =
                  default_schedule
                  // {
                    recursive = true;
                    autosnap = false;
                  };
              };
          };
        }

        (lib.mkIf (replicated != []) {
          fleet.credentials.needs = ["syncoid_ssh_key"];

          # gallium's host key is verified through the fleet SSH CA (@cert-authority
          # in /etc/ssh/ssh_known_hosts).
          services.syncoid = {
            enable = true;

            service.serviceConfig.LoadCredentialEncrypted = "syncoid_ssh_key";

            # Replicate sanoid's snapshots rather than adding syncoid's own.
            commonArgs = ["--no-sync-snap"];

            commands = lib.genAttrs replicated (dataset: {
              target = "syncoid-recv@gallium.gio.ninja:${recvRoot}/${host.name}/${dataset}";
              sshKey = "%d/syncoid_ssh_key";
              # Received unmounted: the recv user has no mount permission.
              recvOptions = "u";
              service.serviceConfig = {
                # oneshot so ExecStartPost waits for a successful send; for the
                # module's default simple type it runs as soon as syncoid starts.
                Type = "oneshot";
                # Marks the first full send done. "+" runs it outside syncoid's
                # chroot, which it cannot chdir in.
                ExecStartPost = "+${pkgs.coreutils}/bin/touch ${initialMarker dataset}";
              };
            });
          };

          # All of a host's jobs would otherwise start at :00 together and trip
          # gallium's sshd MaxStartups. A fixed offset keeps each one hourly.
          systemd.timers = lib.listToAttrs (map (dataset:
            lib.nameValuePair "syncoid-${escapeUnitName dataset}" {
              timerConfig = {
                RandomizedDelaySec = "15m";
                FixedRandomDelay = true;
              };
            })
          replicated);

          # Kick off the first full send on the deploy that adds a dataset instead
          # of waiting for the hourly timer. Retries every boot/switch until a
          # send has succeeded.
          systemd.services = lib.listToAttrs (map (dataset:
            lib.nameValuePair "syncoid-initial-${escapeUnitName dataset}" {
              description = "First full send of ${dataset} to gallium";
              wantedBy = ["multi-user.target"];
              after = ["zfs.target" "network-online.target"];
              wants = ["network-online.target"];
              unitConfig.ConditionPathExists = "!${initialMarker dataset}";
              serviceConfig.Type = "oneshot";
              # --no-sync-snap has nothing to send until sanoid has taken one.
              script = ''
                if ! ${zfs} list -H -t snapshot -o name ${lib.escapeShellArg dataset} | grep -q '@autosnap_'; then
                  systemctl start sanoid.service
                fi
                systemctl start --no-block syncoid-${escapeUnitName dataset}.service
              '';
            })
          replicated);
        })

        (lib.mkIf cfg.makeRecvUser {
          environment.systemPackages = [pkgs.mbuffer pkgs.lzop];

          # Delegated receive rights instead of root, so a compromised sender can
          # add backups but not destroy them.
          systemd.services.syncoid-recv-allow = {
            description = "Delegate ZFS receive on ${recvRoot} to syncoid-recv";
            wantedBy = ["multi-user.target"];
            after = ["zfs.target"];
            serviceConfig = {
              Type = "oneshot";
              RemainAfterExit = true;
              ExecStart = [
                # zfs allow only adds, so clear first to drop rights removed here.
                "-${zfs} unallow -u syncoid-recv ${recvRoot}"
                # receive also checks mount/mountpoint even with -u; the syncoid
                # module's localTargetAllow default, minus change-key.
                "${zfs} allow -u syncoid-recv compression,create,mount,mountpoint,receive,rollback ${recvRoot}"
              ];
            };
          };

          # zfs receive needs each target's parent to exist, and the recv user may
          # not create (mount) it, so make every one declared in fleet.backups.zfs.
          systemd.services.syncoid-recv-parents = {
            description = "Create receiving parents for fleet.backups.zfs";
            wantedBy = ["multi-user.target"];
            after = ["zfs.target"];
            before = ["syncoid-recv-allow.service"];
            serviceConfig = {
              Type = "oneshot";
              RemainAfterExit = true;
            };
            script =
              lib.concatMapStringsSep "\n" (parent: ''
                ${zfs} list -H -o name ${lib.escapeShellArg parent} >/dev/null 2>&1 \
                  || ${zfs} create -p ${lib.escapeShellArg parent}
              '') (lib.unique (lib.concatLists (lib.mapAttrsToList (sender: datasets:
                map (dataset: dirOf "${recvRoot}/${sender}/${dataset}") datasets)
              fleet.backups.zfs)));
          };

          users = {
            users.syncoid-recv = {
              isSystemUser = true;
              group = "syncoid-recv";
              shell = pkgs.bashInteractive;
              openssh.authorizedKeys.keys = [
                # Private half is agevault's syncoid_ssh_key.
                "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMglSONdnmfp0s3fgWmPKdLD7gnhdRmMI0Grgzac77u5"
              ];
            };
            groups.syncoid-recv = {};
          };
        })
      ];
  };
}
