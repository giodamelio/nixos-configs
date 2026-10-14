# TEMP(NIXOS-108): throwaway share proving NFS over TLS before wave 1.
# REMIND-ME-TO: Delete this file and destroy gallium's tank/nfs-test dataset date_passed=2026-10-20
_: {
  fleet.nfs.mounts.nfs-test.gallium."/tank/nfs-test".carbon."/mnt/nfs-test" = {};
}
