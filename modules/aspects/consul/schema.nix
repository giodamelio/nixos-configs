{lib, ...}: let
  inherit (lib) mkOption types;
in {
  den.schema.host.imports = [
    {
      options.consul = {
        enable = mkOption {
          type = types.bool;
          default = false;
          description = "Run a Consul agent on this host (and join the fleet cluster).";
        };
        server = mkOption {
          type = types.bool;
          default = true;
          description = "Run as a Consul server (counts toward bootstrap_expect). false = client agent.";
        };
        webUi = mkOption {
          type = types.bool;
          default = false;
          description = "Serve the Consul web UI on this host.";
        };
      };
    }
  ];
}
