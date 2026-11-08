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
      config.telemetry.dns.enable = lib.mkDefault config.telemetry.cluster.enable;

      options.telemetry = {
        clusterNodes = mkOption {
          type = types.listOf types.str;
          default = ["carbon" "gallium"];
          description = "Hosts that run the telemetry backend. Everything else (storage nodes, tunnels, certificates, route upstreams) is generated from this list.";
        };

        cluster.enable = lib.mkEnableOption ''
          den.aspects.telemetry-cluster on every host that includes
          den.aspects.telemetry-member: alerting, the Caddy front door, push site
          and caddy-l4 tunnels, plus the DNS records. Needs every member enrolled
          (`ca-enroll-host <member> mtls --role telemetry-cluster`) and the
          push_basic_auth_hash and telemetry_pushover_* / telemetry_watchdog_url
          credentials on every member
        '';

        dns.enable = lib.mkEnableOption ''
          the telemetry.gio.ninja and push.telemetry.gio.ninja A records for every
          member. Follows cluster.enable
        '';

        # The LAN, the server VLAN and the UniFi WireGuard clients (oganesson
        # included). Not the IoT VLAN or the OCI VCN.
        pushAllowedRanges = mkOption {
          type = types.listOf types.str;
          default = ["10.0.0.0/16" "10.30.0.0/24" "10.100.0.0/24"];
          description = "Source ranges push.telemetry.gio.ninja accepts; everything else gets 403.";
        };

        crlUpdateInterval = mkOption {
          type = types.str;
          default = "10m";
          description = "How often every client-auth listener refetches the step-ca CRL.";
        };

        ui = {
          enable = lib.mkEnableOption ''
            the caddy-oidc sites vmui, logs and alertmanager.gio.ninja and their DNS
            records. Needs the telemetry_ui_oidc_* credentials on the UI host
          '';
          host = mkOption {
            type = types.str;
            default = "carbon";
            description = "Cluster member that serves the human-facing UIs.";
          };
          adminGroup = mkOption {
            type = types.str;
            # REMIND-ME-TO: Decide the Pocket ID admin group name (NIXOS-150) date_passed=2026-12-01
            default = "telemetry_admin";
            description = "Pocket ID group allowed into Grafana and the caddy-oidc UIs.";
          };
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
