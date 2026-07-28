# gio.telegraf.instances is forwarded verbatim into its own system.services.<name>,
# one telegraf process per entry. Unlike the caddy aspect the instance name is NOT
# prefixed: it becomes the systemd unit name directly, so instances are named for
# their purpose (heartbeat, telegraf-metrics) and existing unit names are kept.
_: {
  den.aspects.telegraf.nixos = {
    lib,
    pkgs,
    config,
    ...
  }: let
    telegrafService = lib.modules.importApply ./_service.nix {inherit pkgs;};
    cfg = config.gio.telegraf;
  in {
    options.gio.telegraf.instances = lib.mkOption {
      type = lib.types.lazyAttrsOf lib.types.deferredModule;
      default = {};
      description = "Each entry is a Telegraf modular service, rendered to system.services.<name>.";
      example = lib.literalExpression ''
        {
          metrics.settings = {
            agent.interval = "60s";
            inputs.cpu = [{totalcpu = true;}];
          };
        }
      '';
    };

    config = lib.mkIf (cfg.instances != {}) {
      system.services =
        lib.mapAttrs (
          name: mod: {
            imports = [telegrafService mod];
            # Irreducible glue: the service module can't know its own instance
            # name, so give each one its own state directory. With DynamicUser
            # systemd backs this with /var/lib/private/<name> owned by that
            # instance's transient UID, so instances cannot read each other's
            # state; a `user`-pinned instance gets /var/lib/<name> owned by it.
            systemd.service.serviceConfig.StateDirectory = lib.mkDefault name;
          }
        )
        cfg.instances;
    };
  };
}
