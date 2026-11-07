_: {
  den.aspects.telemetry-alerting.nixos = {
    fleet,
    host,
    config,
    lib,
    pkgs,
    ...
  }: let
    cfg = config.gio.telemetryAlerting;
    rules = import ./_rules.nix;
    net = import ../network/_lib.nix {inherit lib;};

    members = fleet.telemetry.clusterNodes;
    peers = lib.filter (m: m != host.name) members;
    fqdn = member: "${member}.${fleet.dns.domain}";

    alertmanagerPort = 9093;
    gossipPort = 9094;

    credentialsDir = "/run/credentials/alertmanager.service";
    credentials = {
      pushoverToken = "telemetry_pushover_app_token";
      pushoverUser = "telemetry_pushover_user_token";
      watchdogUrl = "telemetry_watchdog_url";
    };

    # Units read these through LoadCredential, not the root-owned /var/lib/mtls files,
    # because alertmanager runs as a DynamicUser.
    gossipTlsConfig = pkgs.writeText "alertmanager-gossip-tls.yml" (builtins.toJSON {
      tls_server_config = {
        cert_file = "${credentialsDir}/mtls-alertmanager-cert";
        key_file = "${credentialsDir}/mtls-alertmanager-key";
        client_ca_file = "${credentialsDir}/mtls-ca";
        client_auth_type = "RequireAndVerifyClientCert";
        # Any step-ca cert passes the chain check, so peers are also pinned by URI SAN.
        client_allowed_sans = map (member: "spiffe://${fleet.dns.domain}/${member}/alertmanager") members;
      };
      tls_client_config = {
        cert_file = "${credentialsDir}/mtls-alertmanager-cert";
        key_file = "${credentialsDir}/mtls-alertmanager-key";
        ca_file = "${credentialsDir}/mtls-ca";
      };
    });

    alertmanagerUrl = "http://127.0.0.1:${toString alertmanagerPort}";
    peerNotifierUrls = map (peer: "http://127.0.0.1:${toString cfg.peerNotifierPorts.${peer}}") peers;

    # vmalert runs on every cluster member and sends every alert to every Alertmanager.
    # Alertmanager only deduplicates alerts with identical labels, so this config must
    # stay identical across members: never add member-specific labels (e.g.
    # `-external.label=node=...`), or every notification will be sent once per member.
    #
    # Dedup is 1ms because it only needs to collapse identical replicas (replication
    # factor 2) and retried batches. No vmalert recording rules are used. vmalert runs
    # on every cluster member; if recording rules are ever added, each member writes
    # them at slightly different times. In that case either raise
    # `-dedup.minScrapeInterval` on vmselect and vmstorage to the rule evaluation
    # interval (and keep scrape intervals at or above it), or run recording rules on a
    # single member. (Same note as next to the dedup flags in the telemetry aspect.)
    vmalertCommon = {
      "notifier.url" = [alertmanagerUrl] ++ peerNotifierUrls;
    };
  in {
    options.gio.telemetryAlerting.peerNotifierPorts = lib.mkOption {
      type = lib.types.attrsOf lib.types.port;
      default = {};
      example = {gallium = 19093;};
      description = ''
        Local caddy-l4 tunnel port reaching each peer member's Alertmanager web port,
        keyed by member name. Fed from the telemetry aspect's tunnel-port function.
      '';
    };

    config = {
      assertions = [
        {
          assertion = lib.elem host.name members;
          message = "telemetry-alerting: ${host.name} is not in fleet.telemetry.clusterNodes (${toString members}).";
        }
        {
          assertion = lib.all (peer: cfg.peerNotifierPorts ? ${peer}) peers;
          message = "telemetry-alerting: gio.telemetryAlerting.peerNotifierPorts is missing a tunnel port for: ${toString (lib.filter (peer: !(cfg.peerNotifierPorts ? ${peer})) peers)}";
        }
      ];

      gio.mtls.certs.alertmanager = {
        app = "alertmanager";
        role = "telemetry-cluster";
        serverHostnames = [(fqdn host.name)];
        serverAddresses = [(net.theAddress host)];
        services = ["alertmanager.service"];
        onRenew = "restart";
      };

      fleet.credentials.needs = lib.attrValues credentials;

      services.prometheus.alertmanager = {
        enable = true;
        listenAddress = "127.0.0.1";
        port = alertmanagerPort;

        extraFlags =
          [
            "--cluster.listen-address=${net.theAddress host}:${toString gossipPort}"
            "--cluster.advertise-address=${net.theAddress host}:${toString gossipPort}"
            "--cluster.tls-config=${gossipTlsConfig}"
          ]
          ++ map (peer: "--cluster.peer=${fqdn peer}:${toString gossipPort}") peers;

        configuration = {
          route = {
            receiver = "pushover";
            group_by = ["alertname" "host"];
            routes = [
              {
                matchers = [''alertname="Watchdog"''];
                receiver = "watchdog";
                group_by = ["alertname"];
                group_wait = "10s";
                group_interval = "1m";
                repeat_interval = "5m";
              }
            ];
          };
          receivers = [
            {
              name = "pushover";
              pushover_configs = [
                {
                  token_file = "${credentialsDir}/${credentials.pushoverToken}";
                  user_key_file = "${credentialsDir}/${credentials.pushoverUser}";
                  send_resolved = true;
                }
              ];
            }
            {
              name = "watchdog";
              webhook_configs = [
                {
                  url_file = "${credentialsDir}/${credentials.watchdogUrl}";
                  send_resolved = false;
                }
              ];
            }
          ];
        };
      };

      systemd.services.alertmanager.serviceConfig.LoadCredentialEncrypted = [
        credentials.pushoverToken
        credentials.pushoverUser
        credentials.watchdogUrl
      ];

      services.vmalert.instances = {
        metrics = {
          enable = true;
          settings =
            vmalertCommon
            // {
              "datasource.url" = "http://127.0.0.1:8481/select/0/prometheus";
              httpListenAddr = "127.0.0.1:8880";
            };
          rules = rules.metrics;
        };
        logs = {
          enable = true;
          settings =
            vmalertCommon
            // {
              "datasource.url" = "http://127.0.0.1:9428";
              "rule.defaultRuleType" = "vlogs";
              httpListenAddr = "127.0.0.1:8881";
            };
          rules = rules.logs;
        };
      };
    };
  };
}
