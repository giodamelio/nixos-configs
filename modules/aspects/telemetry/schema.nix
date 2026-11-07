{lib, ...}: let
  inherit (lib) mkOption types;

  # Order is part of the tunnel-port scheme: append, never reorder or insert.
  serviceList = [
    {
      name = "vmstorage-insert";
      port = 8400;
    }
    {
      name = "vmstorage-select";
      port = 8401;
    }
    {
      name = "vminsert";
      port = 8480;
    }
    {
      name = "vmselect";
      port = 8481;
    }
    {
      name = "victorialogs";
      port = 9428;
    }
    {
      name = "vlagent";
      port = 9429;
    }
    {
      name = "alertmanager";
      port = 9093;
    }
  ];

  # Tunnel port = base + peerIndex * stride + serviceIndex, where peerIndex is the
  # peer's position in clusterNodes and serviceIndex its position in serviceList.
  # The range sits above every local port (<= 9429) and below the ephemeral range
  # (32768), so it cannot collide with either. Append new members to clusterNodes
  # to keep existing ports stable.
  tunnelBase = 21000;
  tunnelStride = 100;
in {
  den.schema.fleet.imports = [
    ({config, ...}: {
      options.telemetry = {
        clusterNodes = mkOption {
          type = types.listOf types.str;
          default = ["carbon" "gallium"];
          description = "Hosts that run the telemetry backend. Everything else (storage nodes, tunnels, certificates, route upstreams) is generated from this list.";
        };

        retention = {
          metrics = mkOption {
            type = types.str;
            default = "90d";
            description = "vmstorage -retentionPeriod.";
          };
          logs = mkOption {
            type = types.str;
            default = "30d";
            description = "VictoriaLogs -retentionPeriod.";
          };
        };

        services = mkOption {
          readOnly = true;
          type = types.attrsOf types.port;
          default = lib.listToAttrs (map (s: lib.nameValuePair s.name s.port) serviceList);
          description = "Local port of every internal telemetry service.";
        };

        tunnelPorts = mkOption {
          readOnly = true;
          type = types.attrsOf (types.attrsOf types.port);
          default = lib.listToAttrs (lib.imap0 (
              peerIndex: peer:
                lib.nameValuePair peer (lib.listToAttrs (lib.imap0 (
                    serviceIndex: s:
                      lib.nameValuePair s.name (tunnelBase + peerIndex * tunnelStride + serviceIndex)
                  )
                  serviceList))
            )
            config.telemetry.clusterNodes);
          description = "Loopback port on which every member reaches a peer's service through its caddy-l4 tunnel: tunnelPorts.<peer>.<service>.";
        };
      };
    })
  ];
}
