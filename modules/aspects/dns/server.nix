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

    zonesDir = import ./_zones.nix {
      inherit pkgs lib;
      inherit (fleet.dns) zones;
    };
    # Zones are served from here rather than the store so `fleet-dns push` can
    # update them between deploys.
    liveDir = "/var/lib/fleet-dns";

    upstream = lib.concatStringsSep " " fleet.dns.upstream;

    ttlCap =
      lib.optionalString (host.dns.serve.maxTtl != null)
      "rewrite ttl regex .* 0-${toString host.dns.serve.maxTtl}";

    # Names missing from a fleet zone fall through to Cloudflare, whose SOA
    # tells clients to cache the miss for 30 minutes. Capping TTLs here (the
    # rewrite also covers the SOA in the authority section) means a name looked
    # up before its record exists is retried within a minute.
    zoneTtlCap =
      if host.dns.serve.maxTtl == null
      then 60
      else lib.min 60 host.dns.serve.maxTtl;

    # Authoritative fleet zones: answer from the file, fall through to upstream
    # for anything not in the zone.
    zoneBlocks =
      lib.concatStringsSep "\n"
      (lib.mapAttrsToList (name: _zone: ''
          ${name}:53 {
            file ${liveDir}/${name}.zone {
              reload 10s
              fallthrough
            }
            forward . ${upstream}
            rewrite ttl regex .* 0-${toString zoneTtlCap}
            errors
            cache
          }
        '')
        fleet.dns.zones);

    # Forward-only zones (lan -> router, consul -> local agent); mirrors lan-dns.nix.
    forwardBlocks =
      lib.concatStringsSep "\n"
      (lib.mapAttrsToList (zone: resolvers: ''
          ${zone}:53 {
            forward . ${lib.concatStringsSep " " resolvers}
            ${ttlCap}
            errors
            cache
          }
        '')
        fleet.dns.forwardZones);
  in
    lib.mkIf serves {
      # coredns binds 0.0.0.0:53; keep resolved off :53 to avoid a conflict.
      services.resolved.settings.Resolve.DNSStubListener = "no";

      # Install this generation's zones only when they differ from the last ones
      # a deploy installed, so a reboot or a no-op deploy keeps a newer push.
      system.activationScripts.fleet-dns-zones.text = ''
        install -d -m 0755 ${liveDir}
        if [ "$(cat ${liveDir}/.deployed 2>/dev/null)" != "${zonesDir}" ]; then
          for f in ${zonesDir}/*.zone; do
            echo "fleet-dns: installing $(basename "$f") from ${zonesDir}"
            t=$(mktemp -p ${liveDir} .deploy.XXXXXX)
            cat "$f" > "$t"
            chmod 0644 "$t"
            mv -f "$t" "${liveDir}/$(basename "$f")"
          done
          echo "${zonesDir}" > ${liveDir}/.deployed
        else
          echo "fleet-dns: zones unchanged since the last deploy (${zonesDir}), keeping ${liveDir} as is"
        fi
      '';

      services.coredns = {
        enable = true;
        config = ''
          ${zoneBlocks}
          ${forwardBlocks}
          .:53 {
            forward . ${upstream}
            ${ttlCap}
            errors
            cache
          }
        '';
      };

      networking.firewall.allowedTCPPorts = [53];
      networking.firewall.allowedUDPPorts = [53];
    };
}
