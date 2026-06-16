{
  lib,
  config,
  ...
}: let
  net = import ../network/_lib.nix {inherit lib;};
  denHosts = lib.concatMapAttrs (_system: hosts: hosts) config.den.hosts;
  consulHosts = lib.filterAttrs (_n: h: h.consul.enable) denHosts;
  serverHosts = lib.filterAttrs (_n: h: h.consul.enable && h.consul.server) denHosts;
in {
  # Consul cluster membership. Self-gates on host.consul.enable. retry_join and
  # bind interface derive from host.network (replaces homelab.toml join addresses
  # + the hardcoded interface.bind); the gossip key comes from fleet.secrets
  # (replaces gio.credentials). Service registrations are layered on by the
  # services-consul renderer.
  den.aspects.consul.nixos = {
    host,
    lib,
    ...
  }: let
    others = lib.attrNames (lib.filterAttrs (n: _: n != host.name) consulHosts);
    retryJoin = map (n: net.theAddress denHosts.${n}) others;
  in
    lib.mkIf host.consul.enable {
      services.consul = {
        enable = true;
        webUi = host.consul.webUi;
        interface.bind = net.theInterface host;
        # Delivered as a systemd-encrypted credential by the fleet.secrets
        # use-site (secrets.nix) attached to consul.service.
        extraConfigFiles = ["/run/credentials/consul.service/consul-encrypt.json"];
        extraConfig = {
          server = host.consul.server;
          bootstrap_expect = lib.length (lib.attrNames serverHosts);
          retry_join = retryJoin;
          enable_syslog = true;
          addresses.dns = "0.0.0.0";
          telemetry.prometheus_retention_time = "5m";
        };
      };

      # https://developer.hashicorp.com/consul/docs/reference/architecture/ports
      networking.firewall.allowedTCPPorts = [
        8300 # Server RPC
        8301 # LAN serf
        8600 # DNS
      ];
      networking.firewall.allowedUDPPorts = [
        8301 # LAN serf
        8600 # DNS
      ];
    };
}
