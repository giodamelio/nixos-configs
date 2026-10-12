# fleet NFS over TLS: gallium exports two ZFS datasets to carbon. Mount names
# match the legacy shares so the deterministic nfs-<name> uid/gid is preserved
# (forgejo -> 59194, paperless-ngx -> 45450). Both hosts need an NFS
# certificate first (`ca-enroll-host <host> nfs` on strontium).
_: {
  fleet.nfs.mounts = {
    forgejo.gallium."/tank/forgejo".carbon."/mnt/forgejo-repos" = {};
    paperless-ngx.gallium."/tank/paperless".carbon."/mnt/paperless-media" = {};
  };
}
