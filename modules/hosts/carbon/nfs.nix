# fleet NFS over TLS: gallium exports two ZFS datasets to carbon. Mount names
# match the legacy shares so the deterministic nfs-<name> uid/gid is preserved
# (forgejo -> 59194, paperless-ngx -> 45450). Both hosts need an NFS
# certificate first (`ca-enroll-host <host> nfs` on strontium). Each line moves
# into its service's file when that service leaves _staged/.
_: {
  fleet.nfs.mounts = {
    forgejo.gallium."/tank/forgejo".carbon."/var/lib/forgejo/repositories" = {};
    paperless-ngx.gallium."/tank/paperless".carbon."/var/lib/paperless/media" = {};
  };
}
