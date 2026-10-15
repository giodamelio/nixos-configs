# send-metrics — ship journald logs to Loki via Grafana Alloy, and expose node /
# zfs / postgres Prometheus exporters. Shared server aspect. Converted from
# nix/modules/nixos/send-metrics.nix. (Carries its own exporters; do NOT also
# include the `monitoring` aspect on the same host — they'd collide.)
_: {
  den.aspects.send-metrics.nixos = {
    config,
    lib,
    pkgs,
    ...
  }: {
    services.alloy = {
      enable = true;
      # nixpkgs links alloy against systemdLibs, built without compression, so
      # libsystemd silently skips journald's zstd files and loki.source.journal
      # reads nothing. Fixed upstream by NixOS/nixpkgs#571072 (staging, e143584).
      # REMIND-ME-TO: Drop the full-systemd alloy override once nixpkgs#571072 is in our nixos-unstable lock date_passed=2026-11-01
      package = pkgs.grafana-alloy.override {systemdLibs = pkgs.systemd;};
    };

    environment.etc."alloy/config.alloy".text = ''
      loki.write "loki" {
        endpoint {
          url = "https://loki.gio.ninja/loki/api/v1/push"
        }
      }

      loki.source.journal "journald" {
        forward_to    = [loki.write.loki.receiver]
        relabel_rules = loki.relabel.journal.rules
      }

      loki.relabel "journal" {
        forward_to = []

          rule {
              source_labels = ["__journal__systemd_unit"]
              target_label  = "unit"
          }

          rule {
              source_labels = ["__journal__hostname"]
              target_label  = "hostname"
          }

          rule {
              source_labels = ["__journal__priority_keyword"]
              target_label  = "level"
          }

          rule {
              source_labels = ["__journal__transport"]
              target_label  = "transport"
          }

          rule {
              source_labels = ["__journal__comm"]
              target_label  = "command"
          }
      }
    '';

    # Export OS stats.
    services.prometheus = {
      exporters.node = {
        enable = true;
        port = 9000;
        enabledCollectors = [
          "systemd"
        ];
      };

      exporters.zfs = {
        enable = true;
      };
    };

    # Export PostgreSQL metrics.
    services.prometheus.exporters.postgres = lib.mkIf config.services.postgresql.enable {
      enable = true;
      runAsLocalSuperUser = true;
      openFirewall = true;
    };

    # Open the firewall to allow collecting metrics.
    networking.firewall = {
      allowedTCPPorts = [
        config.services.prometheus.exporters.node.port
        config.services.prometheus.exporters.zfs.port
      ];
    };
  };
}
