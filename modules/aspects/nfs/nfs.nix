{
  lib,
  config,
  ...
}: let
  inherit (import ./_types.nix {inherit lib;}) shareId mountsList exportsFor mountsFor peersFor wgPubName;
  denHosts = lib.concatMapAttrs (_system: hosts: hosts) config.den.hosts;
in {
  den.aspects.nfs.nixos = {
    fleet,
    host,
    pkgs,
    lib,
    ...
  }: let
    net = fleet.nfs.network;
    allMounts = fleet.nfs.mounts;

    endpointOf = h: let
      e = denHosts.${h}.nfs.endpoint or null;
    in
      if e != null
      then e
      else h;
    wgIpOf = h: denHosts.${h}.nfs.wgIp;

    peers = peersFor host.name denHosts;
    myExports = exportsFor host.name allMounts;
    myMounts = mountsFor host.name allMounts;

    # `wg set peer` line per peer, reading that peer's pushed public key. Skip a
    # peer whose key has not been delivered yet, so the unit never fails on a
    # missing key — it just converges as credsync delivers them (restartOnChange).
    peerLines = lib.concatMapStringsSep "\n" (p: ''
      if [ -s "$CREDENTIALS_DIRECTORY/${wgPubName p}" ]; then
        wg set ${net.interface} peer "$(cat "$CREDENTIALS_DIRECTORY/${wgPubName p}")" \
          allowed-ips ${wgIpOf p}/32 \
          endpoint ${endpointOf p}:${toString net.port} \
          persistent-keepalive 25
      fi'')
    peers;

    wgUp = pkgs.writeShellApplication {
      name = "wg-nfs-up";
      runtimeInputs = [pkgs.wireguard-tools pkgs.iproute2];
      text = ''
        ip link show ${net.interface} >/dev/null 2>&1 || ip link add dev ${net.interface} type wireguard
        wg set ${net.interface} private-key "$CREDENTIALS_DIRECTORY/wg-priv" listen-port ${toString net.port}
        ${peerLines}
        ip address replace ${wgIpOf host.name}/24 dev ${net.interface}
        ip link set up dev ${net.interface}
      '';
    };
    wgDown = pkgs.writeShellApplication {
      name = "wg-nfs-down";
      runtimeInputs = [pkgs.iproute2];
      text = "ip link del dev ${net.interface} 2>/dev/null || true";
    };

    # NFSv4: each share is exported by its real path and mounted directly (the
    # kernel builds the v4 pseudo-fs; no explicit fsid=0 root needed, matching the
    # legacy nfs-mesh).
    exportLine = m: let
      flag =
        if m.readOnly
        then "ro"
        else "rw";
      id = toString (shareId m.name);
    in "${m.server.path} ${net.subnet}(${flag},sync,no_subtree_check,all_squash,anonuid=${id},anongid=${id})";
  in
    lib.mkIf host.nfs.enable (lib.mkMerge [
      {
        environment.systemPackages = [pkgs.wireguard-tools];

        # Dedicated WG setup unit. Its credentials (own private key + each peer's
        # public key) and the `Requires=/After=secret-*.target` ordering are wired
        # by the fleet.secrets use-sites in secrets.nix — so this starts only once
        # keys are delivered, and re-runs when they change. Decoupled from
        # systemd-networkd, so waiting for network-delivered keys never deadlocks
        # the LAN. Ordered before remote-fs-pre.target so NFS mounts wait for it.
        systemd.services.wg-nfs = {
          description = "WireGuard NFS mesh interface";
          after = ["network-online.target"];
          wants = ["network-online.target"];
          before = ["remote-fs-pre.target"];
          wantedBy = ["remote-fs-pre.target" "multi-user.target"];
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
            ExecStart = lib.getExe wgUp;
            ExecStop = lib.getExe wgDown;
          };
        };

        networking.firewall.allowedUDPPorts = [net.port];

        # Deterministic nfs-<name> user/group on every mesh host, for all_squash.
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

      # Server side: export each share by its real path. NFSv4 needs only TCP
      # 2049, opened on the mesh interface (the v3 RPC ports aren't used).
      (lib.mkIf (myExports != []) {
        services.nfs.server = {
          enable = true;
          exports = lib.concatMapStringsSep "\n" exportLine myExports;
        };
        networking.firewall.interfaces.${net.interface}.allowedTCPPorts = [2049];
      })

      # Client side: the mount + a stable readiness target per mount.
      (lib.mkIf (myMounts != []) {
        # systemd.mounts (not fileSystems) survives the NixOS VM test's
        # mkVMOverride, but unlike fileSystems it doesn't enable the NFS client
        # stack. Setting this flag pulls in rpcbind/idmapd/statd/nfs-client.target
        # (nixos/tasks/filesystems/nfs.nix gates on it) — required for the v4 mount.
        boot.supportedFilesystems = ["nfs"];

        # Ordered after + requiring wg-nfs so the tunnel is up first; wantedBy
        # (Wants) remote-fs.target keeps a first-boot failure (pre-key-delivery)
        # non-fatal.
        systemd.mounts =
          map (m: {
            what = "${wgIpOf m.server.host}:${m.server.path}";
            where = m.client.path;
            type = "nfs";
            # addr= is normally added by the mount.nfs helper; systemd's mount path
            # doesn't, so pass it explicitly (else "didn't pass remote address").
            options = lib.concatStringsSep "," (["nfsvers=4" "noatime" "addr=${wgIpOf m.server.host}"]
              ++ [
                (
                  if m.readOnly
                  then "ro"
                  else "rw"
                )
              ]);
            after = ["wg-nfs.service"];
            requires = ["wg-nfs.service"];
            wantedBy = ["remote-fs.target"];
          })
          myMounts;

        # nfs-<name>.target becomes reachable once the mount is up; services wait
        # on it by name (see the fleet.services nfs-wait bridge). RequiresMountsFor
        # ties it to the mount by path, so no escaped unit name is needed.
        systemd.targets = lib.listToAttrs (map (m:
          lib.nameValuePair "nfs-${m.name}" {
            description = "NFS mount ${m.name} (${m.client.path}) ready";
            unitConfig.RequiresMountsFor = [m.client.path];
          })
        myMounts);
      })
    ]);
}
