{
  lib,
  config,
  ...
}: let
  inherit (import ./_types.nix {inherit lib;}) shareId mountsList exportsFor mountsFor mountTarget;
  net = import ../network/_lib.nix {inherit lib;};
  denHosts = lib.concatMapAttrs (_system: hosts: hosts) config.den.hosts;
in {
  den.aspects.nfs.nixos = {
    config,
    fleet,
    host,
    pkgs,
    lib,
    utils,
    ...
  }: let
    allMounts = fleet.nfs.mounts;
    myExports = exportsFor host.name allMounts;
    myMounts = mountsFor host.name allMounts;
    addressOf = h: net.theAddress denHosts.${h};
    flagOf = m:
      if m.readOnly
      then "ro"
      else "rw";

    # NFSv4: each share is exported by its real path and mounted directly (the
    # kernel builds the v4 pseudo-fs). One client spec per mount, so only the
    # hosts that actually mount a share can reach it.
    clientSpec = m: let
      id = toString (shareId m.name);
    in "${addressOf m.client.host}(${flagOf m},sync,no_subtree_check,all_squash,anonuid=${id},anongid=${id},xprtsec=mtls)";
    exportLines = lib.mapAttrsToList (path: ms: "${path} ${lib.concatMapStringsSep " " clientSpec ms}") (lib.groupBy (m: m.server.path) myExports);
    clientAddresses = lib.unique (map (m: addressOf m.client.host) myExports);

    credDir = "/run/credentials/tlshd.service";
    identity = {
      "x509.truststore" = "${fleet.nfs.caRoot}";
      "x509.certificate" = "${credDir}/cert";
      "x509.private_key" = "${credDir}/key";
    };
  in
    lib.mkIf host.nfs.enable (lib.mkMerge [
      {
        # One step-ca certificate serves both roles: presented to clients as a
        # server and to servers as a client (see cert.nix for its lifecycle).
        system.services.tlshd = {
          imports = [pkgs.ktls-utils.services.default];
          tlshd.settings = {
            "authenticate.client" = identity;
            "authenticate.server" = identity;
          };
          # The key is root-only and tlshd runs as a DynamicUser, so it gets a
          # copy via LoadCredential. That copy is taken at start, which is why
          # enrollment and renewal restart tlshd.
          systemd.service = {
            serviceConfig.LoadCredential = [
              "cert:/var/lib/step-nfs/cert.pem"
              "key:/var/lib/step-nfs/key.pem"
            ];
            # Dormant (not failed) until the host is enrolled.
            unitConfig.ConditionPathExists = "/var/lib/step-nfs/cert.pem";
          };
        };

        # Deterministic nfs-<name> user/group on every NFS host, for all_squash.
        users.users = lib.listToAttrs (map (m:
          lib.nameValuePair "nfs-${m.name}" {
            uid = shareId m.name;
            group = "nfs-${m.name}";
            isSystemUser = true;
          })
        (mountsList allMounts));
        users.groups = lib.listToAttrs (map (m:
          lib.nameValuePair "nfs-${m.name}" {gid = shareId m.name;})
        (mountsList allMounts));
      }

      # Server side. tlshd cannot tie a client certificate to a host (it only
      # checks the chain), so the export ACL and this firewall rule are what
      # restrict each share to its clients' addresses.
      (lib.mkIf (myExports != []) {
        assertions = [
          {
            assertion = config.networking.nftables.enable;
            message = "nfs: ${host.name} exports shares, which needs networking.nftables.enable for the per-client firewall rule";
          }
        ];
        services.nfs.server = {
          enable = true;
          exports = lib.concatStringsSep "\n" exportLines;
        };
        networking.firewall.extraInputRules = ''
          ip saddr { ${lib.concatStringsSep ", " clientAddresses} } tcp dport 2049 accept
        '';
      })

      # Client side: the mount + a stable readiness target per mount.
      (lib.mkIf (myMounts != []) {
        # systemd.mounts (not fileSystems) survives the NixOS VM test's
        # mkVMOverride, but unlike fileSystems it doesn't enable the NFS client
        # stack. Setting this flag pulls in rpcbind/idmapd/statd/nfs-client.target
        # (nixos/tasks/filesystems/nfs.nix gates on it) — required for the v4 mount.
        boot.supportedFilesystems = ["nfs"];

        # The server is named by FQDN because tlshd verifies the server
        # certificate's SAN against it; wantedBy (Wants) remote-fs.target keeps
        # a failed mount from failing the boot.
        systemd.mounts =
          map (m: {
            what = "${m.server.host}.${fleet.dns.domain}:${m.server.path}";
            where = m.client.path;
            type = "nfs";
            # addr= is normally added by the mount.nfs helper; systemd's mount path
            # doesn't, so pass it explicitly (else "didn't pass remote address").
            # proto=tcp pins IPv4: mount.nfs prefers the AAAA record, but exports
            # and the firewall rule are keyed by IPv4 address.
            options = lib.concatStringsSep "," [
              "nfsvers=4.2"
              "proto=tcp"
              "xprtsec=mtls"
              "noatime"
              "addr=${addressOf m.server.host}"
              (flagOf m)
            ];
            after = ["tlshd.service" "network-online.target"];
            wants = ["tlshd.service" "network-online.target"];
            wantedBy = ["remote-fs.target"];
            # Skipped, not hung, until enrolled; nfs-cert-enroll starts them after.
            unitConfig.ConditionPathExists = "/var/lib/step-nfs/cert.pem";
          })
          myMounts;

        # nfs-<name>.target is up exactly while the mount is; services bind to it
        # by name (see the fleet.services nfs-wait bridge), so they never start
        # without the mount and stop if it goes away.
        systemd.targets = lib.listToAttrs (map (m: let
          mountUnit = "${utils.escapeSystemdPath m.client.path}.mount";
        in
          lib.nameValuePair (lib.removeSuffix ".target" (mountTarget m.name)) {
            description = "NFS mount ${m.name} (${m.client.path}) ready";
            bindsTo = [mountUnit];
            after = [mountUnit];
          })
        myMounts);
      })
    ]);
}
