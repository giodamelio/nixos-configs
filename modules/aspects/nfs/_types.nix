{lib}: rec {
  # Hosts participating in the mesh.
  enabledHosts = denHosts: lib.filterAttrs (_name: host: host.nfs.enable) denHosts;

  # Deterministic UID/GID from a mount name, mapped to [10000, 59999].
  # Ported verbatim from nix/modules/nixos/nfs-mesh.nix:11-25.
  hexChars = lib.listToAttrs (lib.imap0 (i: v: {
    name = v;
    value = i;
  }) (lib.stringToCharacters "0123456789abcdef"));
  hexToInt = s: builtins.foldl' (a: b: a * 16 + hexChars.${b}) 0 (lib.stringToCharacters s);
  shareId = name: let
    hash = builtins.hashString "sha256" "nfs-${name}";
    rawInt = hexToInt (builtins.substring 0 8 hash);
  in
    10000 + lib.mod rawInt 50000;

  # Flatten the fluent chain mounts.<name>.<serverHost>.<serverPath>.<clientHost>.<clientPath>
  # into a list of enabled mounts: { name; server={host;path;}; client={host;path;}; readOnly; }.
  #
  # mapAttrsToListRecursiveCond walks the tree to a flat list in one pass,
  # recursing until it reaches the client-path leaves (the only nodes carrying
  # `enable`) and handing each the full key path. The serverPath `path` override
  # is a plain string sibling of the client-host keys, so it's visited too — the
  # null guard drops it; the effective server path is read back from the first
  # three keys.
  mountsList = fleetMounts: let
    toRecord = keys: leaf:
      if !(leaf ? enable)
      then null
      else {
        name = lib.elemAt keys 0;
        server = {
          host = lib.elemAt keys 1;
          inherit ((lib.getAttrFromPath (lib.take 3 keys) fleetMounts)) path;
        };
        client = {
          host = lib.elemAt keys 3;
          inherit (leaf) path;
        };
        inherit (leaf) enable readOnly;
      };
  in
    builtins.filter (m: m != null && m.enable)
    (lib.mapAttrsToListRecursiveCond (_keys: as: !(as ? enable)) toRecord fleetMounts);

  exportsFor = hostName: fleetMounts:
    builtins.filter (m: m.server.host == hostName) (mountsList fleetMounts);
  mountsFor = hostName: fleetMounts:
    builtins.filter (m: m.client.host == hostName) (mountsList fleetMounts);

  # Stable readiness target for a mount name (what fleet.services waits on).
  mountTarget = name: "nfs-${name}.target";

  # Full mesh: every other enabled host.
  peersFor = hostName: denHosts:
    builtins.filter (n: n != hostName) (builtins.attrNames (enabledHosts denHosts));

  wgPrivName = h: "wg-nfs-priv-${h}";
  wgPubName = h: "wg-nfs-pub-${h}";
}
