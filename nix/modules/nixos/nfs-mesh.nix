{
  config,
  lib,
  pkgs,
  ...
}: let
  nfsCfg = config.gio.homelab.nfs;
  homelabNet = config.gio.homelab.networking;
  hostname = config.networking.hostName;

  # Utility functions for deterministic UID/GID from share name
  hexChars = lib.listToAttrs (
    lib.imap0 (i: v: {
      name = v;
      value = i;
    }) (lib.stringToCharacters "0123456789abcdef")
  );
  hexToInt = s: builtins.foldl' (a: b: a * 16 + hexChars.${b}) 0 (lib.stringToCharacters s);

  # Deterministic ID from share name, mapped to [10000, 59999]
  shareId = name: let
    hash = builtins.hashString "sha256" "nfs-${name}";
    rawInt = hexToInt (builtins.substring 0 8 hash);
  in
    10000 + lib.mod rawInt 50000;

  # This host's peer config (assertion guarantees it exists)
  thisPeer = nfsCfg.peers.${hostname};

  # Other peers with non-empty public keys
  otherPeers =
    lib.filterAttrs
    (name: peer: name != hostname && peer.wgPublicKey != "")
    nfsCfg.peers;

  # Shares where this host is the source (NFS server)
  hostExports =
    lib.filterAttrs
    (_name: share: share.source.host == hostname)
    nfsCfg.shares;

  # Shares where this host has a mount entry (NFS client)
  hostMounts =
    lib.filterAttrs
    (_name: share: share.mounts ? ${hostname})
    nfsCfg.shares;

  hasExports = hostExports != {};
  hasMounts = hostMounts != {};

  # WireGuard keygen script using writeShellApplication
  wgNfsKeygen = pkgs.writeShellApplication {
    name = "wg-nfs-keygen";
    runtimeInputs = [pkgs.wireguard-tools pkgs.systemd];
    text = ''
      PRIVKEY=$(wg genkey)
      PUBKEY=$(echo "$PRIVKEY" | wg pubkey)

      install -d -m 0700 /usr/lib/credstore.encrypted
      echo "$PRIVKEY" | systemd-creds encrypt \
        --name=wg-nfs-private-key - \
        /usr/lib/credstore.encrypted/wg-nfs-private-key

      echo "$PUBKEY" > /etc/wireguard-nfs-public-key
      chmod 644 /etc/wireguard-nfs-public-key

      echo "WireGuard NFS mesh public key: $PUBKEY"
      echo "Add this to homelab.nix nfs.peers.${hostname}.wgPublicKey"
    '';
  };

  # Build NFS exports string from all hostExports
  exportLines = let
    pathEntries =
      lib.mapAttrsToList (name: share: {
        inherit (share.source) path;
        uid = shareId name;
        gid = shareId name;
      })
      hostExports;
  in
    lib.concatMapStringsSep "\n" (entry: "${entry.path} 10.100.0.0/24(rw,sync,no_subtree_check,all_squash,anonuid=${toString entry.uid},anongid=${toString entry.gid})")
    pathEntries;

  # Collect all share IDs to check for collisions
  allShareIds =
    lib.mapAttrsToList (name: _: {
      inherit name;
      id = shareId name;
    })
    nfsCfg.shares;

  # Find duplicate IDs
  idCounts = builtins.groupBy (x: toString x.id) allShareIds;
  duplicateIds = lib.filterAttrs (_id: shares: builtins.length shares > 1) idCounts;
in {
  assertions =
    [
      {
        assertion = nfsCfg.peers ? ${hostname};
        message = "nfs-mesh: host '${hostname}' imports nfs-mesh but is not in homelab.nix nfs.peers";
      }
      {
        assertion = config.networking.useNetworkd;
        message = "nfs-mesh: requires networking.useNetworkd = true";
      }
      {
        assertion = duplicateIds == {};
        message = "nfs-mesh: UID/GID collision detected between shares: ${builtins.toJSON duplicateIds}";
      }
    ]
    ++ (lib.mapAttrsToList (name: share: {
        assertion = nfsCfg.peers ? ${share.source.host};
        message = "nfs-mesh: share '${name}' references unknown host '${share.source.host}' as source";
      })
      nfsCfg.shares)
    ++ (lib.flatten (lib.mapAttrsToList (shareName: share:
      lib.mapAttrsToList (mountHost: _: {
        assertion = nfsCfg.peers ? ${mountHost};
        message = "nfs-mesh: share '${shareName}' has mount for unknown host '${mountHost}'";
      })
      share.mounts)
    nfsCfg.shares));

  # WireGuard CLI for debugging
  environment.systemPackages = [pkgs.wireguard-tools];
  # System users and groups for each share (created on ALL mesh hosts)
  users.users = lib.mapAttrs' (name: _share:
    lib.nameValuePair "nfs-${name}" {
      uid = shareId name;
      group = "nfs-${name}";
      isSystemUser = true;
    })
  nfsCfg.shares;

  users.groups = lib.mapAttrs' (name: _share:
    lib.nameValuePair "nfs-${name}" {
      gid = shareId name;
    })
  nfsCfg.shares;

  # WireGuard key auto-generation
  systemd.services.wg-nfs-keygen = {
    description = "Generate WireGuard NFS mesh key pair";
    wantedBy = ["systemd-networkd.service"];
    before = ["systemd-networkd.service"];
    unitConfig.ConditionPathExists = "!/usr/lib/credstore.encrypted/wg-nfs-private-key";
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = false;
      ExecStart = lib.getExe wgNfsKeygen;
    };
  };

  # WireGuard tunnel via systemd-networkd
  systemd.network.netdevs."50-wg-nfs" = {
    netdevConfig = {
      Kind = "wireguard";
      Name = "wg-nfs";
    };
    wireguardConfig = {
      PrivateKeyFile = "/run/credentials/systemd-networkd.service/wg-nfs-private-key";
      ListenPort = 51830;
    };
    wireguardPeers =
      lib.mapAttrsToList (name: peer: let
        peerNet = homelabNet.${name} or null;
        endpoint =
          if peerNet != null
          then peerNet.interfaces.${peerNet.primaryInterface}.address
          else "${name}.gio.ninja";
      in {
        PublicKey = peer.wgPublicKey;
        AllowedIPs = ["${peer.wgIp}/32"];
        Endpoint = "${endpoint}:51830";
        PersistentKeepalive = 25;
      })
      otherPeers;
  };

  systemd.network.networks."50-wg-nfs" = {
    matchConfig.Name = "wg-nfs";
    address = ["${thisPeer.wgIp}/24"];
    networkConfig.IPv6AcceptRA = false;
  };

  # Load WG private key from encrypted credential store
  systemd.services.systemd-networkd.serviceConfig.LoadCredentialEncrypted = [
    "wg-nfs-private-key:/usr/lib/credstore.encrypted/wg-nfs-private-key"
  ];

  # WireGuard UDP port
  networking.firewall.allowedUDPPorts = [51830];

  # NFS server (if this host has exports)
  services.nfs.server = lib.mkIf hasExports {
    enable = true;
    exports = exportLines;
  };

  # NFS port on WG interface only (if exporting)
  networking.firewall.interfaces."wg-nfs".allowedTCPPorts =
    lib.mkIf hasExports [2049];

  # NFS mounts (if this host has mounts)
  fileSystems = lib.mkIf hasMounts (
    lib.foldlAttrs (
      acc: _shareName: share: let
        mountCfg = share.mounts.${hostname};
        serverIp = nfsCfg.peers.${share.source.host}.wgIp;
        rwFlag =
          if mountCfg.readOnly or false
          then "ro"
          else "rw";
      in
        acc
        // {
          "${mountCfg.path}" = {
            device = "${serverIp}:${share.source.path}";
            fsType = "nfs";
            options = ["nfsvers=4" "noatime" "_netdev" "nofail" rwFlag];
          };
        }
    ) {}
    hostMounts
  );
}
