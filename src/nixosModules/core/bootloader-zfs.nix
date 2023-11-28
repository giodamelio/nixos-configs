_: _: {
  boot.initrd.supportedFilesystems = ["zfs"];
  boot.supportedFilesystems = ["zfs"];
  boot.zfs.forceImportRoot = false;
}
