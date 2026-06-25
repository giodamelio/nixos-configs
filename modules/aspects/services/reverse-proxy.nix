{
  lib,
  config,
  ...
}: let
  l = import ./_lib.nix {inherit lib;};
  inherit (import ./_types.nix {inherit lib;}) endpointsOf;
  denHosts = lib.concatMapAttrs (_system: hosts: hosts) config.den.hosts;

  # Fleet-wide invariant: an endpoint domain maps to exactly one DNS record and
  # one Caddy vhost, so it must be unique. A collision would silently drop one
  # (both the vhost map here and serviceZoneRecords in _types.nix key by domain
  # via listToAttrs). Enforced as an assertion below so NO host can build while a
  # duplicate exists — not a separate check that only fails under `nix flake check`.
  dupDomains = l.duplicateDomains (endpointsOf denHosts);
in {
  # Renders each host's local service endpoints into the host-level
  # services.gio.reverse-proxy.virtualHosts (the Caddy-shaping aspect, already
  # pulled in by deployed-apps). DNS-only endpoints (no proxy, no extraConfig)
  # are skipped — they get only a DNS record from the dns-records bridge.
  den.aspects.services-reverse-proxy.nixos = {
    host,
    lib,
    ...
  }: let
    vhosts = lib.listToAttrs (lib.concatLists (lib.mapAttrsToList (_svcName: svc:
      lib.mapAttrsToList (_k: ep: lib.nameValuePair ep.domain (l.endpointToVHost ep))
      (lib.filterAttrs (_k: l.endpointServes) (svc.endpoints or {})))
    (host.services or {})));
  in
    lib.mkMerge [
      {
        assertions = [
          {
            assertion = dupDomains == [];
            message = "fleet.services: endpoint domain(s) declared more than once across the fleet: ${lib.concatStringsSep ", " dupDomains}. Each service domain must be unique (one DNS record + one vhost).";
          }
        ];
      }
      (lib.mkIf (vhosts != {}) {
        services.gio.reverse-proxy = {
          enable = true;
          virtualHosts = vhosts;
        };
      })
    ];
}
