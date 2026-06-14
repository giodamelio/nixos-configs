_: {
  # Authoritative DNS for the fleet zones. Self-gates on the per-host dns.serve
  # fact, so it is inert until a host enables it (mirrors shpool/zmx in den.nix).
  # Any number of hosts may enable it; each serves the same replicated zones.
  den.aspects.dns-server.nixos = {
    fleet,
    host,
    pkgs,
    lib,
    ...
  }: let
    serves = host.dns.enable && host.dns.serve.enable;
    # dns.nix renders each zone (already merged with derived records) to an
    # RFC1035 zone file for coredns's `file` plugin. The zone value was already
    # evaluated by the fleet.dns.zones option (its dns.nix type bakes in the zone
    # name as origin), so coerce it directly — re-running dns.lib.toString would
    # re-evaluate it and clash on the read-only __toString.
    zoneFiles =
      lib.mapAttrs
      (name: zone: pkgs.writeText "${name}.zone" (toString zone))
      fleet.dns.zones;

    upstream = lib.concatStringsSep " " fleet.dns.upstream;

    # Authoritative fleet zones: answer from the file, fall through to upstream
    # for anything not in the zone.
    zoneBlocks =
      lib.concatStringsSep "\n"
      (lib.mapAttrsToList (name: file: ''
          ${name}:53 {
            file ${file} {
              fallthrough
            }
            forward . ${upstream}
            errors
            cache
          }
        '')
        zoneFiles);

    # Forward-only zones (lan -> router, consul -> local agent); mirrors lan-dns.nix.
    forwardBlocks =
      lib.concatStringsSep "\n"
      (lib.mapAttrsToList (zone: resolvers: ''
          ${zone}:53 {
            forward . ${lib.concatStringsSep " " resolvers}
            errors
            cache
          }
        '')
        fleet.dns.forwardZones);
  in
    lib.mkIf serves {
      # coredns binds 0.0.0.0:53; keep resolved off :53 to avoid a conflict.
      services.resolved.settings.Resolve.DNSStubListener = "no";

      services.coredns = {
        enable = true;
        config = ''
          ${zoneBlocks}
          ${forwardBlocks}
          .:53 {
            forward . ${upstream}
            errors
            cache
          }
        '';
      };

      networking.firewall.allowedTCPPorts = [53];
      networking.firewall.allowedUDPPorts = [53];
    };
}
