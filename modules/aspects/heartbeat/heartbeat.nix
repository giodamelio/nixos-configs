# heartbeat — per-host Telegraf that folds the signals preceding a slow failure
# (SMART wear, disk/pool full, zpool degraded, failed units, WAN loss, SSH cert
# expiry) into ONE verdict per period and pushes it to this host's own
# Healthchecks.io check: the ok path is a heartbeat (dead-man's switch via grace),
# the fail path (URL/fail) pages with the reason. No central hub. Attached to a
# host by including den.aspects.server-heartbeat. The raw metrics are also served
# on :62791 for debugging and for the future rich-metrics layer to scrape.
{inputs, ...}: {
  den.aspects.heartbeat.nixos = {
    lib,
    config,
    pkgs,
    ...
  }: let
    inherit (lib) mkOption types;
    cfg = config.gio.heartbeat;

    metricsPort = 62791;

    zfsEnabled = config.boot.supportedFilesystems.zfs or false;

    probe = inputs.self.lib.writeNushellApplication pkgs {
      name = "heartbeat-probe";
      runtimeInputs = [pkgs.openssh pkgs.systemd] ++ lib.optional zfsEnabled pkgs.zfs;
      source = builtins.readFile ./heartbeat-probe.nu;
    };

    collectInterval = "${toString cfg.intervalSeconds}s";
    pushInterval = "${toString cfg.pushSeconds}s";

    # Categories that MUST be seen each period or the verdict trips stale:<cat>.
    # smart is opportunistic (driveless hosts emit none); the rest are required
    # where their input runs. Matches the input set built below.
    required = lib.concatStringsSep "," (
      ["disk" "failed_units"]
      ++ lib.optional zfsEnabled "zpool"
      ++ lib.optional cfg.checkInternet "internet"
      ++ lib.optional cfg.checkSshCert "ssh_cert"
    );

    # Measurement names the aggregator consumes (the raw signals). Subset per host
    # so absent inputs aren't listed.
    signalNames =
      ["disk" "smart_device" "systemd_health"]
      ++ lib.optional zfsEnabled "zpool_health"
      ++ lib.optional cfg.checkInternet "ping"
      ++ lib.optional cfg.checkSshCert "ssh_cert";

    hcTemplate = ''{{ .Field "message" }}'';

    telegrafConf = {
      agent = {
        interval = collectInterval;
        flush_interval = collectInterval;
        omit_hostname = false;
      };

      inputs =
        {
          disk = [{ignore_fs = cfg.ignoreFs;}];
          smart = [{attributes = false;}];
          exec =
            [
              {
                commands = ["${probe}/bin/heartbeat-probe failed-units"];
                timeout = "5s";
                data_format = "influx";
              }
            ]
            ++ lib.optional zfsEnabled {
              commands = ["${probe}/bin/heartbeat-probe zpool"];
              timeout = "5s";
              data_format = "influx";
            }
            ++ lib.optional cfg.checkSshCert {
              commands = ["${probe}/bin/heartbeat-probe ssh-cert"];
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

      # THE combiner: many raw signals -> one `health` metric per period. All the
      # threshold/missing-signal logic lives in the starlark; the http outputs
      # below are dumb serializers. drop_original keeps the raw metrics flowing to
      # prometheus_client for debugging.
      aggregators.starlark = [
        {
          period = pushInterval;
          drop_original = false;
          namepass = signalNames;
          source = builtins.readFile ./heartbeat-verdict.star;
          constants = {
            disk_full = cfg.diskUsedPercent + 0.0;
            ssh_cert_min_seconds = cfg.sshCertMinDays * 86400 + 0.0;
            ttl_seconds = cfg.intervalSeconds * 3;
            inherit required;
          };
        }
      ];

      # Exactly one fires per period: the aggregator's single `result` tag routes
      # ok -> base URL (heartbeat), fail -> URL/fail (page). Identical body: the
      # full snapshot, so every ping is a live health view in Healthchecks.
      outputs.http = [
        {
          url = "\${HC_URL}";
          method = "POST";
          data_format = "template";
          template = hcTemplate;
          tagpass.result = ["ok"];
        }
        {
          url = "\${HC_URL}/fail";
          method = "POST";
          data_format = "template";
          template = hcTemplate;
          tagpass.result = ["fail"];
        }
      ];

      # Unfiltered detail: current value of every raw metric plus health_failed,
      # Prometheus text. Curl it when an alert fires; scrapeable by the future
      # rich-metrics layer.
      outputs.prometheus_client = [
        {
          listen = ":${toString metricsPort}";
          metric_version = 2;
        }
      ];
    };

    configFile = (pkgs.formats.toml {}).generate "heartbeat.conf" telegrafConf;

    # Reads this host's Healthchecks ping URL from the systemd credential and
    # hands it to Telegraf via ${HC_URL} (outputs.http.url isn't a secret-capable
    # field, so env substitution — not a secretstore — is the delivery path).
    runner = pkgs.writeShellApplication {
      name = "heartbeat-run";
      runtimeInputs = [pkgs.coreutils pkgs.telegraf];
      text = ''
        HC_URL="$(cat "$CREDENTIALS_DIRECTORY/healthcheck_url")"
        export HC_URL
        exec telegraf --config ${configFile}
      '';
    };
  in {
    options.gio.heartbeat = {
      metricsPort = mkOption {
        type = types.port;
        readOnly = true;
        default = metricsPort;
        description = "Port serving the full metric detail (Prometheus text). Fixed/read-only.";
      };

      intervalSeconds = mkOption {
        type = types.int;
        default = 60;
        description = "How often signals are collected locally. The stale-signal TTL is 3x this.";
      };

      pushSeconds = mkOption {
        type = types.int;
        default = 240;
        description = "How often the combined verdict is pushed to Healthchecks. Kept just under the HC 5m period; should be a multiple of intervalSeconds so each push has fresh collections behind it.";
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
        description = "Check the step-ca SSH host cert isn't near expiry. Required signal: a missing cert trips stale:ssh_cert, so leave off until the host is enrolled.";
      };

      sshCertMinDays = mkOption {
        type = types.int;
        default = 7;
        description = "Trip when the SSH host cert has fewer than this many days left (30d validity, daily renewal).";
      };
    };

    # Attached only where a host includes den.aspects.server-heartbeat, so
    # attachment is the enablement — no separate on/off fact.
    config = {
      fleet.credentials.needs = ["healthcheck_url"];

      systemd.services.heartbeat = {
        description = "Telegraf health verdict -> Healthchecks push";
        wantedBy = ["multi-user.target"];
        after = ["network.target"];
        path = [pkgs.smartmontools pkgs.nvme-cli] ++ lib.optional zfsEnabled pkgs.zfs;

        serviceConfig = {
          ExecStart = lib.getExe runner;
          LoadCredentialEncrypted = ["healthcheck_url"];
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

      networking.firewall.allowedTCPPorts = [metricsPort];
    };
  };
}
