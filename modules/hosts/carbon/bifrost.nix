# bifrost on carbon: the only thing the gateway forwards (public 443 ->
# carbon:52793). Its state lives on bowl/bifrost so it rides the backups.
{den, ...}: {
  den.aspects.carbon.includes = [den.aspects.bifrost];

  den.aspects.carbon.nixos = {
    # carbon's own cluster member (den.aspects.nats); it has no client auth.
    gio.bifrost.nats.url = "nats://127.0.0.1:4222";

    gio.bifrost.login.clientId = "107d56fb-5157-485e-af6e-f040744253fc";

    disko.devices.zpool.bowl.datasets.bifrost = {
      type = "zfs_fs";
      mountpoint = "/var/lib/bifrost";
      options = {
        mountpoint = "legacy";
        atime = "off";
      };
    };
  };

  # A redirect, not a proxy: the admin login's OIDC callback and cookie are
  # bound to the auth host.
  den.hosts.x86_64-linux.carbon.services.bifrost-admin.endpoint = {
    domain = "bifrost";
    extraConfig = "redir https://auth.external.gio.ninja/admin";
  };

  fleet.backups.zfs.carbon = ["bowl/bifrost"];

  # LAN clients reach bifrost through the internal Caddy (gio.bifrost.lanProxy)
  # with their real addresses, instead of hairpinning through the gateway.
  fleet.dns.zones."gio.ninja".subdomains."*.external".CNAME = ["carbon.gio.ninja."];
}
