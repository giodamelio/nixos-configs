# Thin wrapper around the Caddy modular service (./_service.nix). Each entry of
# gio.caddy.instances is forwarded verbatim into its own system.services.caddy-<n>
# unit, so a host can run several independent Caddy servers (own vhosts, settings,
# plugins). The wrapper adds no options of its own beyond the entry point — only
# the host-class glue the portable service structurally can't set.
_: {
  den.aspects.caddy.nixos = {
    lib,
    pkgs,
    config,
    ...
  }: let
    caddyService = lib.modules.importApply ./_service.nix {inherit pkgs;};
    cfg = config.gio.caddy;
  in {
    options.gio.caddy.instances = lib.mkOption {
      type = lib.types.lazyAttrsOf lib.types.deferredModule;
      default = {};
      description = "Each entry is a Caddy modular service, rendered to system.services.caddy-<name>.";
      example = lib.literalExpression ''
        {
          public.virtualHosts."https://example.com".extraConfig = "respond 200";
        }
      '';
    };

    config = lib.mkIf (cfg.instances != {}) {
      system.services =
        lib.mapAttrs' (
          name: mod:
            lib.nameValuePair "caddy-${name}" {
              imports = [caddyService mod];
              # Irreducible glue: the service module can't know its own unit name,
              # so give each instance distinct state/log paths and its own admin
              # socket — otherwise every process would fight over /var/lib/caddy and
              # the default admin port (127.0.0.1:2019).
              dataDir = lib.mkDefault "/var/lib/caddy-${name}";
              logDir = lib.mkDefault "/var/log/caddy-${name}";
              adminEndpoint = lib.mkDefault "unix//run/caddy-${name}/admin.sock";
              systemd.service.serviceConfig.RuntimeDirectory = lib.mkDefault "caddy-${name}";
            }
        )
        cfg.instances;

      # QUIC buffer sizes — host-class, so they live here rather than in the
      # portable service. https://github.com/quic-go/quic-go/wiki/UDP-Buffer-Sizes
      boot.kernel.sysctl = {
        "net.core.rmem_max" = lib.mkDefault 2500000;
        "net.core.wmem_max" = lib.mkDefault 2500000;
      };
    };
  };
}
