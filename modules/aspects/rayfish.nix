_: {
  den.aspects.rayfish.nixos = {
    lib,
    config,
    perSystem,
    ...
  }: let
    cfg = config.gio.rayfish;
    ray = lib.getExe' perSystem.giopkgs.rayfish "ray";
  in {
    options.gio.rayfish.enable = lib.mkEnableOption "the rayfish P2P mesh VPN daemon";

    config = {
      environment.systemPackages = [perSystem.giopkgs.rayfish];

      systemd.services.rayfish = lib.mkIf cfg.enable {
        description = "rayfish P2P mesh VPN daemon";
        wantedBy = ["multi-user.target"];
        after = ["network-online.target"];
        wants = ["network-online.target"];

        serviceConfig = {
          # Runs as root: the daemon creates the TUN device and rewrites system
          # DNS (resolvconf / systemd-resolved) for Magic DNS.
          ExecStart = "${ray} daemon";
          Restart = "on-failure";
          RestartSec = 5;

          # The control socket path is hardcoded to /run/rayfish/rayfish.sock;
          # let systemd own the dir (create + tear down, correct perms).
          RuntimeDirectory = "rayfish";

          # No StateDirectory / XDG_CONFIG_HOME: rayfish hardcodes its entire
          # config tree to /etc/rayfish (settings.toml, per-network configs, and
          # the node's identity secret), independent of $XDG_CONFIG_HOME/$HOME.
          # /etc persists on the root fs, so the daemon's state survives reboots
          # with no extra wiring.
        };
      };
    };
  };
}
