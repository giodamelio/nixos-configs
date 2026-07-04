# health-collector — per-host Telegraf that turns the signals preceding a slow
# hardware death (SMART wear, disk/pool full, zpool degraded) into one 200/503
# verdict on :port/ for rhodium's Gatus to poll. No metrics store. Wired
# fleet-wide via den.default; runs where the host fact monitor.enable is set.
{inputs, ...}: {
  den.aspects.health-collector.nixos = {
    host,
    lib,
    config,
    pkgs,
    ...
  }: let
    inherit (lib) mkOption mkIf types;
    cfg = config.gio.health-collector;
    ports = import ./_lib.nix;

    zfsEnabled = config.boot.supportedFilesystems.zfs or false;

    # One nushell app with a subcommand per exec probe; each prints influx line
    # protocol (see health-probe.nu). zfs only where present, to keep it out of
    # e.g. rhodium's closure.
    probe = inputs.self.lib.writeNushellApplication pkgs {
      name = "health-probe";
      runtimeInputs = [pkgs.openssh pkgs.systemd] ++ lib.optional zfsEnabled pkgs.zfs;
      source = builtins.readFile ./health-probe.nu;
    };

    diskFull = cfg.diskUsedPercent + 0.0;
    sshCertMinSeconds = cfg.sshCertMinDays * 86400 + 0.0;

    # Each compare is the HEALTHY condition; it only touches metrics carrying its
    # field, so NVMe-only and SATA-only fields share one endpoint without colliding.
    smartCompares = [
      # smartctl exited clean; non-zero = query error or self-assessed failure.
      {
        field = "exit_status";
        le = 0.0;
      }
      # Bad sectors that failed a read and are queued to be remapped. Any = trouble.
      {
        field = "pending_sector_count";
        le = 0.0;
      }
      # Sectors already remapped to spares after going bad. Any = surface wear.
      {
        field = "reallocated_sectors_count";
        le = 0.0;
      }
      # Sectors unreadable even after retries — unrecoverable, real data-loss risk.
      {
        field = "uncorrectable_sector_count";
        le = 0.0;
      }
      # SATA link CRC errors — usually a flaky cable/connection rather than the drive.
      {
        field = "udma_crc_errors";
        le = 0.0;
      }
      # NVMe: media / data-integrity errors the controller caught. Any = failing flash.
      {
        field = "media_errors";
        le = 0.0;
      }
      # NVMe: controller critical-warning bitmask (spare low, read-only, overtemp…).
      {
        field = "critical_warning";
        le = 0.0;
      }
      # NVMe: percent of spare blocks left; falls toward the ~10% threshold as it dies.
      {
        field = "available_spare";
        gt = 10.0;
      }
      # NVMe: percent of rated write endurance consumed. Healthy under 90% used.
      {
        field = "percentage_used";
        le = 90.0;
      }
      # SATA SSD: percent of rated life remaining (Crucial et al). Healthy over 10% left.
      {
        field = "percent_lifetime_remain";
        ge = 10.0;
      }
    ];

    telegrafConf = {
      agent = {
        interval = "60s";
        flush_interval = "60s";
        omit_hostname = false;
      };

      inputs =
        {
          disk = [{ignore_fs = cfg.ignoreFs;}];
          # summary fields need no attributes=true; 5-min cadence is gentle on drives.
          smart = [
            {
              attributes = false;
              interval = "300s";
            }
          ];
          # failed-unit count always; zpool helper only where ZFS is present.
          exec =
            [
              {
                commands = ["${probe}/bin/health-probe failed-units"];
                timeout = "5s";
                data_format = "influx";
              }
            ]
            ++ lib.optional zfsEnabled {
              commands = ["${probe}/bin/health-probe zpool"];
              timeout = "5s";
              data_format = "influx";
            }
            ++ lib.optional cfg.checkSshCert {
              commands = ["${probe}/bin/health-probe ssh-cert"];
              timeout = "5s";
              data_format = "influx";
            };
        }
        // lib.optionalAttrs cfg.checkInternet {
          # native ICMP to a raw IP (no DNS in the path) = WAN reachability.
          ping = [
            {
              urls = [cfg.internetTarget];
              count = 3;
              method = "native";
            }
          ];
        };

      outputs.health = [
        {
          service_address = "http://:${toString cfg.port}";
          namepass =
            ["disk" "smart_device" "systemd_health"]
            ++ lib.optional zfsEnabled "zpool_health"
            ++ lib.optional cfg.checkInternet "ping"
            ++ lib.optional cfg.checkSshCert "ssh_cert";
          compares =
            [
              # Any mount at/above the fill threshold (slow out-of-space failure).
              {
                field = "used_percent";
                lt = diskFull;
              }
              # Failed systemd units — dead / crash-looping service. Healthy at zero.
              {
                field = "failed_units";
                le = 0.0;
              }
            ]
            ++ smartCompares
            ++ lib.optionals zfsEnabled [
              # zpool not ONLINE (DEGRADED/FAULTED) — missing/failed member.
              {
                field = "degraded";
                le = 0.0;
              }
              # zpool capacity at/above the fill threshold.
              {
                field = "capacity";
                lt = diskFull;
              }
            ]
            ++ lib.optional cfg.checkInternet {
              # 100% loss = the internet is unreachable from this host.
              field = "percent_packet_loss";
              lt = 100.0;
            }
            ++ lib.optional cfg.checkSshCert {
              # SSH host cert time-to-expiry; low = step-ca renewal is stalling.
              field = "expiry_seconds";
              gt = sshCertMinSeconds;
            };
        }
      ];

      # Unfiltered detail endpoint: current value of every metric (Prometheus
      # text, labeled by drive/mount/pool). Curl it when an alert fires.
      outputs.prometheus_client = [
        {
          listen = ":${toString cfg.metricsPort}";
          metric_version = 2;
        }
      ];
    };

    configFile = (pkgs.formats.toml {}).generate "telegraf-health.conf" telegrafConf;
  in {
    options.gio.health-collector = {
      # Fixed, read-only (shared with the fleet-monitor via ./_lib.nix): readable
      # by other modules, settable by none.
      port = mkOption {
        type = types.port;
        readOnly = true;
        default = ports.healthPort;
        description = "Port the health verdict (pass/fail) is served on. Fixed/read-only.";
      };

      metricsPort = mkOption {
        type = types.port;
        readOnly = true;
        default = ports.metricsPort;
        description = "Port serving the full metric detail (Prometheus text). Fixed/read-only.";
      };

      diskUsedPercent = mkOption {
        type = types.int;
        default = 90;
        description = "Trip the verdict when any mount (or zpool) is at/above this fill %.";
      };

      ignoreFs = mkOption {
        type = types.listOf types.str;
        default = ["tmpfs" "devtmpfs" "devfs" "overlay" "aufs" "squashfs" "iso9660" "nsfs" "efivarfs" "ramfs"];
        description = "Filesystem types excluded from the disk-full check.";
      };

      checkInternet = mkOption {
        type = types.bool;
        default = true;
        description = "Fold WAN reachability (native ICMP ping) into the verdict.";
      };

      internetTarget = mkOption {
        type = types.str;
        default = "1.1.1.1";
        description = "Raw IP to ping for the connectivity check (kept an IP so DNS is never in the path).";
      };

      checkSshCert = mkOption {
        type = types.bool;
        default = true;
        description = "Check the step-ca SSH host cert isn't near expiry (stalled renewal). Inert where no cert exists.";
      };

      sshCertMinDays = mkOption {
        type = types.int;
        default = 7;
        description = "Trip when the SSH host cert has fewer than this many days left (30d validity, daily renewal).";
      };
    };

    config = mkIf host.monitor.enable {
      systemd.services.telegraf-health = {
        description = "Telegraf health-verdict collector (SMART/disk/zpool -> :${toString cfg.port})";
        wantedBy = ["multi-user.target"];
        after = ["network.target"];
        # zfs only where present; smartctl/nvme for the SMART input.
        path = [pkgs.smartmontools pkgs.nvme-cli] ++ lib.optional zfsEnabled pkgs.zfs;

        serviceConfig = {
          ExecStart = "${pkgs.telegraf}/bin/telegraf --config ${configFile}";
          Restart = "always";
          RestartSec = 10;

          # Root: NVMe admin passthrough and /dev/zfs are both root-only, so
          # capability-scoping would still need CAP_SYS_ADMIN. Sandboxed below.
          # No SystemCallFilter — it'd risk breaking SMART/zpool ioctls silently.
          NoNewPrivileges = true;
          ProtectHome = true;
          ProtectSystem = "strict"; # verdict is in-memory; nothing is written
          PrivateTmp = true;
          ProtectControlGroups = true;
          ProtectKernelModules = true;
          ProtectKernelTunables = true;
          RestrictAddressFamilies = ["AF_INET" "AF_INET6" "AF_UNIX"];
          RestrictNamespaces = true;
          RestrictRealtime = true;
          LockPersonality = true;
          MemoryDenyWriteExecute = true;
        };
      };

      networking.firewall.allowedTCPPorts = [cfg.port cfg.metricsPort];
    };
  };
}
