_: {
  config,
  lib,
  ...
}: {
  services.prometheus = {
    exporters = {
      node = {
        enable = true;
        enabledCollectors = ["systemd"];
        listenAddress = "0.0.0.0";
      };

      # Enable the ZFS exporter if zfs is used in the system
      # TODO: think of a better way to check if ZFS is used
      zfs = lib.mkIf (builtins.hasAttr "zfs" config.boot.supportedFilesystems) {
        enable = true;
      };
    };
  };

  # Configure Telegraf to send stats to to TSDB
  services.telegraf = {
    enable = true;
    extraConfig = {
      inputs = {
        # System Stats
        cpu = {};
        disk = {};
        diskio = {};
        internet_speed = {
          interval = "60m";
        };
        kernel = {};
        linux_sysctl_fs = {};
        mem = {};
        net = {
          # Setting this to false is deprecated
          # See: https://github.com/influxdata/telegraf/blob/master/plugins/inputs/net/README.md
          ignore_protocol_stats = true;
        };
        netstat = {};
        nstat = {};
        processes = {};
        # TODO: fix this
        # smart = {
        #   path_smartctl = "${pkgs.smartmontools}/bin/smartctl";
        #   path_nvme = "${pkgs.nvme-cli}/bin/nvme";
        # };
        swap = {};
        system = {};
        systemd_units = [
          {unittype = "service";}
          {unittype = "timer";}
        ];
        zfs = {
          poolMetrics = true;
          datasetMetrics = true;
        };

        # TODO: Fix this, what are the minimum permissions it needs to function
        # Monitor PostgreSQL
        # postgresql = {
        #   address = "host=/run/postgresql user=telegraf sslmode=disable";
        # };

        # Monitor Wireguard
        wireguard = {};
      };
      outputs.postgresql = {
        connection = "host=zirconium.gio.ninja user=telegraf dbname=metrics sslmode=disable";

        # Make it work with TSDB
        tags_as_foreign_keys = true;
        create_templates = [
          "CREATE TABLE {{ .table }} ({{ .columns }})"
          "SELECT create_hypertable({{ .table|quoteLiteral }}, by_range('time', INTERVAL '1 week'), if_not_exists := true)"
        ];
      };
    };
  };

  systemd.services.telegraf = {
    # Give Telegraf CAP_NET_ADMIN so it can talk to Wireguard via netlink
    serviceConfig = {
      CapabilityBoundingSet = "CAP_NET_ADMIN";
      AmbientCapabilities = "CAP_NET_ADMIN";
      LoadCredentialEncrypted = "telegraf-postgres-passfile";
    };

    environment = {
      PGPASSFILE = "%d/telegraf-postgres-passfile";
    };
  };

  networking.firewall.interfaces."wg9" = {
    allowedTCPPorts = [
      config.services.prometheus.exporters.node.port
      config.services.prometheus.exporters.zfs.port
    ];
  };
}
