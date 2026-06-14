{
  lib,
  inputs,
  ...
}: {
  den.schema.host.imports = [
    {
      # Participate in the fleet DNS system. false = this host is invisible to
      # DNS: no A record derived, excluded from ns.<domain>, never a server.
      options.dns.enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Whether this host takes part in the fleet DNS system.";
      };

      # Stopgap host-networking fact until a real network aspect exists. A host
      # with a static IP gets an A record (and service domains on it resolve to
      # that IP instead of a CNAME).
      options.dns.ip = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Static LAN IP of this host, or null if not known.";
      };

      # Run the authoritative DNS server on this host. A submodule (not a bare
      # bool) so server-specific settings can be added later. Any number of
      # hosts may enable it; each serves the same fleet zones (replicated).
      options.dns.serve = lib.mkOption {
        default = {};
        description = "Authoritative DNS server settings for this host.";
        type = lib.types.submodule {
          options.enable = lib.mkOption {
            type = lib.types.bool;
            default = false;
            description = "Run the fleet's authoritative DNS server here.";
          };
        };
      };
    }
  ];

  den.schema.fleet.imports = [
    {
      options.dns = {
        domain = lib.mkOption {
          type = lib.types.str;
          default = "gio.ninja";
          description = ''
            The primary fleet zone. Host A records and service-endpoint records
            are merged into `zones.<domain>` automatically.
          '';
        };
        zones = lib.mkOption {
          # nix-community/dns.nix zone type: records of each kind are lists that
          # merge across modules, so explicit + derived records combine cleanly.
          type = lib.types.attrsOf inputs.dns.lib.types.zone;
          default = {};
          description = ''
            DNS zones, keyed by zone name (e.g. "gio.ninja"). Declare records the
            dns.nix way, e.g. `zones."gio.ninja".subdomains.www.A = ["10.0.0.1"]`.
          '';
        };
        upstream = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = ["1.1.1.1" "1.0.0.1"];
          description = "Upstream resolvers for the catch-all and zone fallthrough.";
        };
        forwardZones = lib.mkOption {
          type = lib.types.attrsOf (lib.types.listOf lib.types.str);
          default = {
            lan = ["10.0.0.1"];
            consul = ["127.0.0.1:8600"];
          };
          description = ''
            Zones the server forwards rather than answers authoritatively, zone ->
            [resolvers]. Mirrors lan-dns.nix's `lan` (router) and `consul` blocks.
          '';
        };
      };
    }
  ];
}
