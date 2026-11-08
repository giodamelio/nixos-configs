{
  den,
  lib,
  config,
  ...
}: let
  net = import ../network/_lib.nix {inherit lib;};
  denHosts = lib.concatMapAttrs (_system: hosts: hosts) config.den.hosts;
in {
  # What a member host includes. Until fleet.telemetry.cluster.enable it gets
  # only what runs without enrollment or secrets and leaves Caddy untouched.
  den.aspects.telemetry-member.includes =
    if config.fleet.telemetry.cluster.enable
    then [den.aspects.telemetry-cluster]
    else [
      den.aspects.telemetry-backend
      den.aspects.telemetry-agent
      den.aspects.telemetry-node-certs
    ];

  # Declared ahead of their consumers, so strontium can enroll a member before
  # the cluster is turned on and turning it on needs no second enrollment.
  den.aspects.telemetry-node-certs.nixos = {
    fleet,
    host,
    ...
  }: let
    identity = {
      role = "telemetry-cluster";
      serverHostnames = ["${host.name}.${fleet.dns.domain}"];
      serverAddresses = [(net.theAddress host)];
    };
  in {
    gio.mtls.certs = {
      telemetry-node = identity // {onRenew = "reload-caddy";};
      alertmanager = identity // {onRenew = "restart";};
    };
  };

  den.aspects.telemetry-cluster.includes = [
    den.aspects.reverse-proxy
    den.aspects.telemetry-backend
    den.aspects.telemetry-alerting
    den.aspects.telemetry-agent
    den.aspects.telemetry-node-certs
  ];

  den.aspects.telemetry-cluster.nixos = {
    config,
    fleet,
    host,
    lib,
    ...
  }: let
    cfg = fleet.telemetry;
    domain = fleet.dns.domain;
    members = cfg.clusterNodes;
    peers = lib.filter (m: m != host.name) members;
    ports = cfg.services;
    loopback = "127.0.0.1";
    fqdn = member: "${member}.${domain}";
    selfAddress = net.theAddress host;
    peerAddresses = map (peer: net.theAddress denHosts.${peer}) peers;
    gossipPort = 9094;
    vmstorageHttpPort = 8482;

    cert = config.gio.mtls.certs.telemetry-node;
    caRoot = config.gio.mtls.caRoot;
    crlDir = "/var/lib/caddy/crl";
    credentialsDir = "/run/credentials/caddy.service";
    pushHash = "push_basic_auth_hash";

    # The CRL is found through each certificate's CDP, never crl_url: a crl_url
    # that cannot be fetched at startup fails the whole config load, taking every
    # site down whenever strontium is unreachable at boot. crl_cdp_strict fails
    # closed until the CRL has loaded once; disk storage keeps the last CRL across
    # restarts and strontium outages. crl_only because step-ca has no OCSP.
    revocation = ''
      verifier revocation {
        mode crl_only
        crl_config {
          storage_type disk
          work_dir ${crlDir}
          update_interval ${cfg.crlUpdateInterval}
          signature_validation_mode verify
          cdp_config {
            crl_fetch_mode fetch_actively
            crl_cdp_strict true
          }
        }
      }
    '';

    clientAuth = ''
      client_auth {
        mode require_and_verify
        trust_pool file ${caRoot}
        ${lib.optionalString config.gio.telemetry-cluster.checkRevocation revocation}
      }
    '';

    allowedCns = map (member: "telemetry-node.${member}") members;

    listener = port: ''
      ${selfAddress}:${toString port} {
        route {
          tls {
            connection_policy {
              ${clientAuth}
            }
          }
        }
        @member vars {l4.tls.client.subject.common_name} ${lib.concatStringsSep " " allowedCns}
        route @member {
          proxy ${loopback}:${toString port}
        }
      }
    '';

    tunnel = peer: service: ''
      ${loopback}:${toString cfg.tunnelPorts.${peer}.${service}} {
        route {
          proxy {
            upstream ${fqdn peer}:${toString ports.${service}} {
              tls
              tls_server_name ${fqdn peer}
              tls_trust_pool file ${caRoot}
              tls_client_auth ${cert.certFile} ${cert.keyFile}
            }
          }
        }
      }
    '';

    # Local first, then each peer's tunnel. lb_try_duration retries a refused
    # local dial on the next upstream instead of waiting for the health check.
    proxyTo = service: ''
      reverse_proxy ${lib.concatStringsSep " " (
        ["${loopback}:${toString ports.${service}}"]
        ++ map (peer: "${loopback}:${toString cfg.tunnelPorts.${peer}.${service}}") peers
      )} {
        lb_policy first
        lb_try_duration 5s
        health_uri /health
      }
    '';

    # {http.request.tls.client.subject} is Go's pkix.Name.String() (RFC 2253
    # order, last RDN first): "CN=vmagent.carbon,OU=telemetry-writer,O=app" for
    # an app certificate. Values escape ',' as '\,', so [^,]+ cannot run into
    # the next field. Only the app provisioner sets an OU, so this also pins the
    # issuing provisioner.
    subjectWithRole = role: "^CN=[^,]+,OU=${role},O=app$";

    frontDoor = ''
      log_append client_subject {http.request.tls.client.subject}

      handle_path /metrics/* {
        # Remote write only: vminsert's other ingest formats are unused here.
        @insert {
          vars_regexp {http.request.tls.client.subject} ${subjectWithRole "telemetry-writer"}
          path_regexp ^/insert/[0-9]+/prometheus/api/v1/write$
        }
        handle @insert {
          ${proxyTo "vminsert"}
        }

        # Read-only Prometheus query API. vmselect also serves delete_series,
        # graphite delSeries and cache resets on these prefixes without
        # -deleteAuthKey, so only named query endpoints pass.
        @select {
          vars_regexp {http.request.tls.client.subject} ${subjectWithRole "telemetry-reader"}
          path_regexp ^/select/[0-9]+/prometheus/api/v1/(query|query_range|query_exemplars|series|labels|label/[^/]+/values|metadata|status/buildinfo)$
        }
        handle @select {
          ${proxyTo "vmselect"}
        }

        handle {
          respond 403
        }
      }

      handle_path /logs/* {
        # journal-upload's protocol only; nothing else writes logs through here.
        @insert {
          vars_regexp {http.request.tls.client.subject} ${subjectWithRole "telemetry-writer"}
          path /insert/journald/upload
        }
        handle @insert {
          ${proxyTo "vlagent"}
        }

        # LogsQL queries only: VictoriaLogs also serves /delete/* tasks and the
        # vmui and vmalert proxies.
        @select {
          vars_regexp {http.request.tls.client.subject} ${subjectWithRole "telemetry-reader"}
          path_regexp ^/select/logsql/(query|hits|stats_query|stats_query_range|query_time_range|facets|field_names|field_values|stream_field_names|stream_field_values|streams|stream_ids)$
        }
        handle @select {
          ${proxyTo "victorialogs"}
        }

        handle {
          respond 403
        }
      }

      handle {
        respond 403
      }
    '';

    pushSite = ''
      route {
        @outside not remote_ip ${lib.concatStringsSep " " cfg.pushAllowedRanges}
        respond @outside 403

        # VictoriaLogs reads stream, ignore, extra-field and tenant settings from
        # these headers too; the rewrites below must be the only ones.
        request_header -AccountID
        request_header -ProjectID
        request_header -VL-*

        basic_auth {
          push {file.${credentialsDir}/${pushHash}}
        }
        request_body {
          max_size 1MB
        }

        # Each rewrite replaces the whole query string, so a pusher cannot add
        # or override labels or fields.
        handle /prometheus {
          rewrite * /insert/0/prometheus/api/v1/import/prometheus?extra_label=source=push
          ${proxyTo "vminsert"}
        }
        handle /influx {
          rewrite * /insert/0/influx/write?extra_label=source=push
          ${proxyTo "vminsert"}
        }
        handle /logs {
          rewrite * /insert/jsonline?_stream_fields=source&extra_fields=source=push
          # VictoriaLogs reads its query parameters with FormValue, which swallows
          # an x-www-form-urlencoded body (curl -d's default) and ingests nothing.
          request_header Content-Type application/stream+json
          ${proxyTo "vlagent"}
        }
        handle {
          respond 404
        }
      }
    '';

    internalPorts = lib.attrValues ports ++ [gossipPort];
  in {
    options.gio.telemetry-cluster.checkRevocation = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Check the step-ca CRL on every client-auth listener.";
    };

    config = {
      assertions = [
        {
          assertion = config.networking.nftables.enable;
          message = "telemetry-cluster: the member-only port rules use extraInputRules, which needs networking.nftables.enable";
        }
      ];

      gio.mtls.certs.telemetry-node.services = ["caddy"];

      fleet.credentials.needs = [pushHash];
      systemd.services.caddy.serviceConfig.LoadCredentialEncrypted = [pushHash];

      systemd.tmpfiles.rules = ["d ${crlDir} 0700 caddy caddy - -"];

      services.gio.reverse-proxy = {
        enable = true;
        virtualHosts = {
          telemetry = {
            reverseProxy = false;
            tlsExtraConfig = clientAuth;
            extraConfig = frontDoor;
          };
          "push.telemetry" = {
            reverseProxy = false;
            extraConfig = pushSite;
          };
        };
      };

      services.caddy = {
        # The Caddyfile has no global way to load a certificate file, and the
        # layer4 TLS handler only serves certificates the tls app holds. This site
        # loads it; its name is the certificate's own DNS SAN.
        virtualHosts."https://${fqdn host.name}".extraConfig = ''
          tls ${cert.certFile} ${cert.keyFile}
          respond 404
        '';

        globalConfig = ''
          layer4 {
            ${lib.concatMapStrings listener (lib.attrValues ports)}
            ${lib.concatStrings (lib.concatMap (peer: map (tunnel peer) (lib.attrNames ports)) peers)}
          }
        '';
      };

      # Alertmanager gossip runs TLS over TCP only (--cluster.tls-config), so 9094/udp stays closed.
      networking.firewall.extraInputRules = ''
        ip saddr { ${lib.concatStringsSep ", " peerAddresses} } ip daddr ${selfAddress} tcp dport { ${lib.concatMapStringsSep ", " toString internalPorts} } accept
      '';

      gio.telemetryAlerting.peerNotifierPorts = lib.genAttrs peers (peer: cfg.tunnelPorts.${peer}.alertmanager);

      gio.telemetry-agent.extraScrapeTargets = let
        local = port: {targets = ["${loopback}:${toString port}"];};
      in {
        vmstorage = local vmstorageHttpPort;
        vminsert = local ports.vminsert;
        vmselect = local ports.vmselect;
        victorialogs = local ports.victorialogs;
        vlagent = local ports.vlagent;
        vmalert-metrics.targets = [config.services.vmalert.instances.metrics.settings.httpListenAddr];
        vmalert-logs.targets = [config.services.vmalert.instances.logs.settings.httpListenAddr];
        alertmanager = local config.services.prometheus.alertmanager.port;
      };
    };
  };
}
