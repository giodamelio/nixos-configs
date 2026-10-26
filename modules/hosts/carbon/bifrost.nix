# bifrost on carbon: the only thing the gateway forwards (public 443 ->
# carbon:52793). Its state lives on bowl/bifrost so it rides the backups.
{den, ...}: {
  den.aspects.carbon.includes = [den.aspects.bifrost];

  den.aspects.carbon.nixos = {lib, ...}: {
    gio.bifrost.login.clientId = lib.mkDefault (throw "bifrost: create the bifrost OIDC client in Pocket ID (redirect URI https://auth.external.gio.ninja/callback, group bifrost) and put its client ID in modules/hosts/carbon/bifrost.nix");

    disko.devices.zpool.bowl.datasets.bifrost = {
      type = "zfs_fs";
      mountpoint = "/var/lib/bifrost";
      options = {
        mountpoint = "legacy";
        atime = "off";
      };
    };
  };

  fleet.backups.zfs.carbon = ["bowl/bifrost"];

  # LAN clients reach bifrost through the internal Caddy (gio.bifrost.lanProxy)
  # with their real addresses, instead of hairpinning through the gateway.
  fleet.dns.zones."gio.ninja".subdomains."*.external".CNAME = ["carbon.gio.ninja."];
}
