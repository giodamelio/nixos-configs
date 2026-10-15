_: {
  # Registers each local service in Consul (on by default per service via
  # consul.enable). Only active on hosts that run a Consul agent (host.consul.
  # enable, from the consul cluster aspect). Checks are derived from the service's
  # healthcheck facet.
  den.aspects.services-consul.nixos = {
    host,
    fleet,
    lib,
    ...
  }: let
    l = import ./_lib.nix {inherit lib;};
    regs = l.consulRegistrationsOf fleet.dns.domain (host.services or {});
  in
    lib.mkIf (host.consul.enable && regs != []) {
      environment.etc."consul.d/fleet-services.json".text = builtins.toJSON {services = regs;};
      services.consul.extraConfigFiles = ["/etc/consul.d/fleet-services.json"];
    };
}
