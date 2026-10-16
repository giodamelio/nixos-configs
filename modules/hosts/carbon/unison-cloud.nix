{den, ...}: {
  den.aspects.carbon.includes = [den.aspects.unison-cloud];

  den.aspects.carbon.nixos = {config, ...}: {
    disko.devices.zpool.bowl.datasets.unison-cloud = {
      type = "zfs_fs";
      mountpoint = config.services.unison-cloud.stateDir;
      options = {
        mountpoint = "legacy";
        atime = "off";
      };
    };
  };

  # DNS-only: the aspect serves these vhosts itself.
  den.hosts.x86_64-linux.carbon.services = {
    unison-cloud-api = {
      endpoint.domain = "api.unison";
      healthcheck.target = "https://api.unison.gio.ninja/.well-known/openid-configuration";
    };
    unison-cloud-apps.endpoint.domain = "app.unison";
    unison-cloud-ui.endpoint.domain = "unison";
  };

  fleet.backups.zfs.carbon = ["bowl/unison-cloud"];
}
