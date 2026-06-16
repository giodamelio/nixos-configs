{
  lib,
  config,
  ...
}: let
  denHosts = lib.concatMapAttrs (_system: hosts: hosts) config.den.hosts;
  consulHosts = lib.attrNames (lib.filterAttrs (_n: h: h.consul.enable) denHosts);
  # Deterministic origin: the cluster's gossip key is generated once on the
  # sorted-first consul host and pushed to the rest via the use-sites.
  origin =
    if consulHosts == []
    then null
    else lib.head (lib.sort (a: b: a < b) consulHosts);
in {
  config.fleet.secrets = lib.mkIf (origin != null) {
    consul-encrypt = {
      inherit origin;
      generator = {
        script = ''printf '{"encrypt":"%s"}' "$(consul keygen)"'';
        path = pkgs: [pkgs.consul];
      };
      use = lib.genAttrs consulHosts (_host: {
        services.consul = {
          credential.name = "consul-encrypt.json";
          restartOnChange = true;
        };
      });
    };
  };
}
