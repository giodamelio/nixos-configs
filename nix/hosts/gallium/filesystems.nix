{
  fileSystems."/" = {
    device = "boot/root";
    fsType = "zfs";
  };

  fileSystems."/nix" = {
    device = "boot/nix";
    fsType = "zfs";
  };

  fileSystems."/home" = {
    device = "boot/home";
    fsType = "zfs";
  };

  fileSystems."/boot" = {
    device = "/dev/disk/by-uuid/E22B-1CDA";
    fsType = "vfat";
    options = ["fmask=0022" "dmask=0022"];
  };

  # fileSystems."/tank/attic" = {
  #   device = "tank/attic";
  #   fsType = "zfs";
  # };
  #
  # fileSystems."/tank/garage" = {
  #   device = "tank/garage";
  #   fsType = "zfs";
  # };
  #
  # fileSystems."/tank/garage/data" = {
  #   device = "tank/garage/data";
  #   fsType = "zfs";
  # };
  #
  # fileSystems."/tank/garage/metadata" = {
  #   device = "tank/garage/metadata";
  #   fsType = "zfs";
  # };
  #
  # fileSystems."/tank/garage/metadata_snapshots" = {
  #   device = "tank/garage/metadata_snapshots";
  #   fsType = "zfs";
  # };
  #
  # fileSystems."/tank/garage/config" = {
  #   device = "tank/garage/config";
  #   fsType = "zfs";
  # };
  #
  # fileSystems."/tank/hard-drive-dumping-zone" = {
  #   device = "tank/hard-drive-dumping-zone";
  #   fsType = "zfs";
  # };
  #
  # fileSystems."/tank/isos" = {
  #   device = "tank/isos";
  #   fsType = "zfs";
  # };
  #
  # fileSystems."/tank/syncthing" = {
  #   device = "tank/syncthing";
  #   fsType = "zfs";
  # };
  #
  # fileSystems."/tank/photos-dump" = {
  #   device = "tank/photos-dump";
  #   fsType = "zfs";
  # };
}
