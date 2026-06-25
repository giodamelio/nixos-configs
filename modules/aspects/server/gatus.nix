# gatus — opt-in status page. Enable it on a host and declare checks; each check
# is mostly a URL, with conditions derived from a few friendly knobs (status,
# maxResponseTime, bodyContains) plus a raw `conditions` escape hatch. This is NOT
# wired to the fleet.services registry — add a check explicitly when you want one.
_: {
  den.aspects.gatus.nixos = {
    lib,
    config,
    ...
  }: let
    inherit (lib) mkOption mkEnableOption mkIf types;
    cfg = config.gio.gatus;

    checkType = types.submodule ({name, ...}: {
      options = {
        name = mkOption {
          type = types.str;
          default = name;
          defaultText = lib.literalExpression "<attr name>";
          description = "Display name on the status page.";
        };
        group = mkOption {
          type = types.str;
          default = "Services";
          description = "Group to list this check under.";
        };
        type = mkOption {
          type = types.enum ["http" "tcp" "icmp"];
          default = "http";
          description = "Check kind.";
        };
        url = mkOption {
          type = types.nullOr types.str;
          default = null;
          description = "Target URL (required for http checks).";
        };
        host = mkOption {
          type = types.nullOr types.str;
          default = null;
          description = "Target \"host:port\" (tcp) or \"host\" (icmp).";
        };
        status = mkOption {
          type = types.int;
          default = 200;
          description = "Expected HTTP status (http checks).";
        };
        maxResponseTime = mkOption {
          type = types.nullOr types.str;
          default = null;
          description = "Max response time, e.g. \"300ms\" / \"1s\" -> [RESPONSE_TIME] < N (ms).";
        };
        bodyContains = mkOption {
          type = types.nullOr types.str;
          default = null;
          description = "Substring the response body must contain.";
        };
        interval = mkOption {
          type = types.str;
          default = "60s";
          description = "How often to run the check.";
        };
        conditions = mkOption {
          type = types.nullOr (types.listOf types.str);
          default = null;
          description = "Raw gatus conditions; when set, overrides all derived ones (escape hatch).";
        };
      };
    });

    # "300ms" -> 300, "1s" -> 1000 (gatus wants a bare ms integer).
    rtMs = s: let
      m = builtins.match "([0-9]+)(ms|s)?" s;
      n = lib.toInt (lib.head m);
    in
      if (lib.elemAt m 1) == "s"
      then n * 1000
      else n;

    endpointOf = c: let
      url =
        if c.type == "tcp"
        then "tcp://${c.host}"
        else if c.type == "icmp"
        then "icmp://${c.host}"
        else c.url;
      derived =
        lib.optional (c.type == "http") "[STATUS] == ${toString c.status}"
        ++ lib.optional (c.type == "tcp" || c.type == "icmp") "[CONNECTED] == true"
        ++ lib.optional (c.maxResponseTime != null) "[RESPONSE_TIME] < ${toString (rtMs c.maxResponseTime)}"
        ++ lib.optional (c.bodyContains != null) "[BODY] == pat(*${c.bodyContains}*)";
    in {
      inherit (c) name group interval;
      inherit url;
      conditions =
        if c.conditions != null
        then c.conditions
        else derived;
    };
  in {
    options.gio.gatus = {
      enable = mkEnableOption "Gatus status page";
      port = mkOption {
        type = types.int;
        default = 4444;
        description = "Web UI port (front it with the reverse proxy).";
      };
      checks = mkOption {
        type = types.attrsOf checkType;
        default = {};
        description = "Status-page checks. Each is mostly a URL; conditions derive from the knobs.";
      };
    };

    config = mkIf cfg.enable {
      assertions =
        lib.mapAttrsToList (n: c: {
          assertion =
            if c.type == "http"
            then c.url != null
            else c.host != null;
          message = "gio.gatus.checks.${n}: ${
            if c.type == "http"
            then "http checks need `url`"
            else "${c.type} checks need `host`"
          }";
        })
        cfg.checks;

      services.gatus = {
        enable = true;
        settings = {
          web.port = cfg.port;
          metrics = true;
          storage = {
            type = "sqlite";
            path = "/var/lib/gatus/data.db";
          };
          endpoints = lib.mapAttrsToList (_n: endpointOf) cfg.checks;
        };
      };
    };
  };
}
