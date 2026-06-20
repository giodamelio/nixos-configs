# fleet.nfs mesh: gallium exports two ZFS datasets to carbon over WireGuard.
# Mount names match the legacy shares so the deterministic nfs-<name> uid/gid is
# preserved (forgejo -> 59194, paperless-ngx -> 45450). The WG keypairs are
# generated per host by the fleet.nfs/fleet.secrets aspects (no manual keygen).
# Converted from homelab.nix nfs.shares + nix/modules/nixos/nfs-mesh.nix.
_: {
  fleet.nfs.mounts = {
    forgejo.gallium."/tank/forgejo".carbon."/mnt/forgejo-repos" = {};
    paperless-ngx.gallium."/tank/paperless".carbon."/mnt/paperless-media" = {};
  };
}
