_: {
  den.aspects.telemetry-agent.nixos = {
    config,
    lib,
    pkgs,
    ...
  }: let
    inherit (lib) mkOption types;
    cfg = config.gio.telemetry-agent;
    exporters = config.services.prometheus.exporters;
    hostName = config.networking.hostName;

    vmagentCredDir = "%d";
    journalUploadCredDir = "/run/credentials/systemd-journal-upload.service";

    localTargets = lib.filterAttrs (_: target: target.enable) {
      node = {
        enable = exporters.node.enable;
        address = "127.0.0.1:${toString exporters.node.port}";
      };
      zfs = {
        enable = exporters.zfs.enable;
        address = "127.0.0.1:${toString exporters.zfs.port}";
      };
      postgres = {
        enable = exporters.postgres.enable;
        address = "127.0.0.1:${toString exporters.postgres.port}";
      };
      process = {
        enable = exporters.process.enable;
        address = "${exporters.process.listenAddress}:${toString exporters.process.port}";
      };
    };

    scrapeJob = name: {
      metricsPath,
      targets,
      scheme,
      ...
    }: {
      job_name = name;
      metrics_path = metricsPath;
      inherit scheme;
      static_configs = [
        {
          inherit targets;
          labels = {
            host = hostName;
            instance = hostName;
          };
        }
      ];
    };
  in {
    options.gio.telemetry-agent = {
      remoteWriteUrl = mkOption {
        type = types.str;
        default = "https://telemetry.gio.ninja/metrics/insert/0/prometheus/api/v1/write";
      };

      journalUploadUrl = mkOption {
        type = types.str;
        default = "https://telemetry.gio.ninja:443/logs/insert/journald";
        description = ''
          journal-upload appends `/upload`. The port must be explicit: without
          one it appends `:19532/upload` after the path instead.
        '';
      };

      bufferMaxBytes = mkOption {
        type = types.str;
        default =
          if pkgs.stdenv.hostPlatform.isAarch64
          then "256MiB"
          else "2GiB";
        defaultText = "256MiB on aarch64, 2GiB elsewhere";
        description = "Cap on vmagent's on-disk remote write buffer, with a size suffix.";
      };

      extraScrapeTargets = mkOption {
        default = {};
        description = "Additional local scrape jobs, keyed by job name.";
        example = {
          vmstorage.targets = ["127.0.0.1:8482"];
        };
        type = types.attrsOf (types.submodule {
          options = {
            targets = mkOption {type = types.listOf types.str;};
            metricsPath = mkOption {
              type = types.str;
              default = "/metrics";
            };
            scheme = mkOption {
              type = types.enum ["http" "https"];
              default = "http";
            };
          };
        });
      };

      journalUploadNetworkTimeout = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = ''
          journal-upload has no connect-timeout option. This sets curl's total
          request timeout, so leave it unset unless long-lived uploads are fine
          being cut.
        '';
      };
    };

    config = {
      services.prometheus.exporters = {
        node = {
          enable = lib.mkDefault true;
          port = lib.mkDefault 9000;
          enabledCollectors = lib.mkDefault ["systemd"];
        };
        process = {
          enable = true;
          listenAddress = "127.0.0.1";
          settings.process_names = [
            {
              name = "{{.Comm}}";
              cmdline = [".+"];
            }
          ];
        };
      };

      gio.mtls.certs = {
        vmagent = {
          app = "vmagent";
          role = "telemetry-writer";
          services = ["vmagent.service"];
          onRenew = "restart";
        };
        journal-upload = {
          app = "journal-upload";
          role = "telemetry-writer";
          services = ["systemd-journal-upload.service"];
          onRenew = "restart";
        };
      };

      services.vmagent = {
        enable = true;
        remoteWrite.url = cfg.remoteWriteUrl;
        prometheusConfig = {
          global.scrape_interval = "15s";
          scrape_configs =
            lib.mapAttrsToList (name: target:
              scrapeJob name {
                targets = [target.address];
                metricsPath = "/metrics";
                scheme = "http";
              })
            localTargets
            ++ lib.mapAttrsToList scrapeJob cfg.extraScrapeTargets;
        };
        extraArgs = [
          "-remoteWrite.tlsCertFile=${vmagentCredDir}/mtls-vmagent-cert"
          "-remoteWrite.tlsKeyFile=${vmagentCredDir}/mtls-vmagent-key"
          "-remoteWrite.maxDiskUsagePerURL=${cfg.bufferMaxBytes}"
          # vmagent has no dial-timeout flag; these bound the TLS handshake and a single send.
          "-remoteWrite.tlsHandshakeTimeout=5s"
          "-remoteWrite.sendTimeout=30s"
        ];
      };

      services.journald.upload = {
        enable = true;
        settings.Upload =
          {
            URL = cfg.journalUploadUrl;
            ServerCertificateFile = "${journalUploadCredDir}/mtls-journal-upload-cert";
            ServerKeyFile = "${journalUploadCredDir}/mtls-journal-upload-key";
            TrustedCertificateFile = config.security.pki.caBundle;
          }
          // lib.optionalAttrs (cfg.journalUploadNetworkTimeout != null) {
            NetworkTimeoutSec = cfg.journalUploadNetworkTimeout;
          };
      };
    };
  };
}
