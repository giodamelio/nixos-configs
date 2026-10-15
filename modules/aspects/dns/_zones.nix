# One <zone>.zone file per fleet zone. Shared by the DNS servers (installed on
# deploy) and `fleet-dns push`, so both always ship byte-identical zones.
{
  pkgs,
  lib,
  zones,
}: let
  # The zone value was already evaluated by the fleet.dns.zones option (its
  # dns.nix type bakes in the zone name as origin), so coerce it directly —
  # re-running dns.lib.toString would re-evaluate it and clash on the read-only
  # __toString.
  render = name: zone: let
    text = toString zone;
    # coredns `reload` only re-reads a zone whose SOA serial changed (its
    # reload_by_mtime never records the mtime, so it reloads every tick), so
    # derive the serial from the records. 7 hex digits stays under 2^32.
    serial = toString (lib.fromHexString (builtins.substring 0 7 (builtins.hashString "sha256" text)));
    parts = builtins.split "\\(1 " text;
  in
    if builtins.length parts != 3
    then throw "fleet-dns: zone ${name} does not have exactly one SOA with serial 1 to replace"
    else lib.replaceStrings ["(1 "] ["(${serial} "] text;
in
  pkgs.linkFarm "fleet-dns-zones" (lib.mapAttrsToList (name: zone: {
      name = "${name}.zone";
      path = pkgs.writeText "${name}.zone" (render name zone);
    })
    zones)
