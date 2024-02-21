_: {pkgs, ...}: {
  boot.initrd.supportedFilesystems = ["zfs"];
  boot.supportedFilesystems = ["zfs"];
  boot.zfs.forceImportRoot = false;

  environment.systemPackages = [pkgs.httm];
}
