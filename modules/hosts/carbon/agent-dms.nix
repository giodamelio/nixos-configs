# agent-dms — Stalwart mail server (agent-dms.gio.ninja) giving each project's
# coding agents an inbox. Fastmail is the public MX; fetchmail pulls from it.
# Config lives in postgres, applied by stalwart-apply.
_: let
  domain = "agent-dms.gio.ninja";
  httpPort = 8091;
  lmtpPort = 24;
  fastmailCredential = "fastmail_agent_dms_imap";
in {
  den.aspects.carbon.nixos = {
    pkgs,
    lib,
    ...
  }: let
    stalwart = pkgs.stalwart_0_16;
    stateDir = "/var/lib/stalwart";
    adminFile = "${stateDir}/recovery-admin";

    dataStore = pkgs.writeText "stalwart-config.json" (builtins.toJSON {
      "@type" = "PostgreSql";
      host = "/run/postgresql";
      # Also names the socket file, .s.PGSQL.5432.
      port = 5432;
      database = "stalwart";
      authUsername = "stalwart";
      authSecret."@type" = "None";
    });

    # NDJSON, one stalwart-cli apply operation per line. Client ids ("#dom")
    # share one namespace across the whole plan.
    plan = pkgs.writeText "stalwart-plan.ndjson" (lib.concatMapStrings (op: builtins.toJSON op + "\n") [
      {
        "@type" = "upsert";
        object = "DnsServer";
        matchOn = ["description"];
        value.cf = {
          "@type" = "Cloudflare";
          description = "cloudflare";
          secret = {
            "@type" = "File";
            filePath = "/run/credentials/stalwart.service/caddy_cloudflare_api_token";
          };
        };
      }
      {
        "@type" = "upsert";
        object = "AcmeProvider";
        matchOn = ["directory"];
        value.acme = {
          directory = "https://acme-v02.api.letsencrypt.org/directory";
          contact."mailto:gio@damelio.net" = true;
          challengeType = "Dns01";
        };
      }
      {
        "@type" = "upsert";
        object = "Domain";
        matchOn = ["name"];
        value.dom = {
          name = domain;
          certificateManagement = {
            "@type" = "Automatic";
            acmeProviderId = "#acme";
            # Without SANs a DNS-01 order also asks for *.agent-dms.gio.ninja.
            subjectAlternativeNames.${domain} = true;
          };
          # DNS-01 needs automatic DNS management, and the first certificate
          # order is chained after a DNS publish that fails with nothing to
          # publish. CAA is the one record that's harmless in the public zone.
          dnsManagement = {
            "@type" = "Automatic";
            dnsServerId = "#cf";
            publishRecords.caa = true;
          };
        };
      }
      {
        "@type" = "upsert";
        object = "Account";
        matchOn = ["name"];
        value.gio = {
          "@type" = "User";
          name = "gio";
          domainId = "#dom";
        };
      }
      {
        "@type" = "upsert";
        object = "Application";
        matchOn = ["description"];
        value.webui = {
          description = "Stalwart Web Interface";
          enabled = true;
          resourceUrl = "file://${stalwart.webui}/webui.zip";
          urlPrefix = {
            "/admin" = true;
            "/account" = true;
          };
        };
      }
      {
        "@type" = "update";
        object = "SystemSettings";
        value = {
          defaultHostname = domain;
          defaultDomainId = "#dom";
        };
      }
      {
        "@type" = "update";
        object = "Http";
        # Only the 127.0.0.1 listener speaks HTTP, so the header is always Caddy's.
        value.useXForwarded = true;
      }
      {
        "@type" = "update";
        object = "Sharing";
        value.maxShares = 25;
      }
      {
        "@type" = "update";
        object = "Authentication";
        value.maxAppPasswords = 10;
      }
      {
        "@type" = "update";
        object = "MtaStageData";
        # Fastmail already filtered what fetchmail hands over, and every LMTP
        # session looks like it comes from 127.0.0.1.
        value.enableSpamFilter = {
          match."0" = {
            "if" = "listener == 'lmtp'";
            "then" = "false";
          };
          "else" = "is_empty(authenticated_as)";
        };
      }
      # Last: it moves the listener this run may be talking to, and destroys
      # the default ones (25, 443, 995, 4190).
      {
        "@type" = "reconcile";
        object = "NetworkListener";
        matchOn = ["name"];
        value = {
          http = {
            name = "http";
            bind."127.0.0.1:${toString httpPort}" = true;
            protocol = "http";
            useTls = false;
          };
          imaps = {
            name = "imaps";
            bind."[::]:993" = true;
            protocol = "imap";
            useTls = true;
            tlsImplicit = true;
          };
          submissions = {
            name = "submissions";
            bind."[::]:465" = true;
            protocol = "smtp";
            useTls = true;
            tlsImplicit = true;
          };
          lmtp = {
            name = "lmtp";
            bind."127.0.0.1:${toString lmtpPort}" = true;
            protocol = "lmtp";
            useTls = false;
          };
        };
      }
    ]);

    # The recovery admin is the provisioner too: it impersonates any account
    # with no permission check, which is what `agent-dms init` needs. Generated
    # here rather than in agevault so first boot needs no manual step; copy it
    # into 1Password once.
    start = pkgs.writeShellApplication {
      name = "stalwart-start";
      runtimeInputs = [pkgs.coreutils pkgs.openssl];
      text = ''
        # The server rewrites config.json, so it can't be a store symlink.
        install -m 0600 ${dataStore} ${stateDir}/config.json
        if [[ ! -s ${adminFile} ]]; then
          (umask 077 && printf 'admin:%s\n' "$(openssl rand -hex 24)" > ${adminFile})
        fi
        STALWART_RECOVERY_ADMIN="$(cat ${adminFile})"
        export STALWART_RECOVERY_ADMIN
        exec ${lib.getExe stalwart} --config ${stateDir}/config.json
      '';
    };

    apply = pkgs.writeShellApplication {
      name = "stalwart-apply";
      runtimeInputs = [pkgs.stalwart-cli];
      text = ''
        admin="$(cat ${adminFile})"
        export STALWART_USER="''${admin%%:*}" STALWART_PASSWORD="''${admin#*:}"
        # Before the first apply moves it, the HTTP listener is the default
        # one on 8080.
        if ! stalwart-cli --url http://127.0.0.1:${toString httpPort} apply --file ${plan}; then
          echo "stalwart-apply: falling back to the default listener on 8080" >&2
          stalwart-cli --url http://127.0.0.1:8080 apply --file ${plan}
        fi
      '';
    };

    # IDLE on Fastmail's AgentDMs folder; X-Delivered-to is the envelope
    # recipient Fastmail stamps above everything the sender wrote. softbounce
    # leaves anything Stalwart refuses in Fastmail instead of bouncing it.
    fetchmailStart = pkgs.writeShellApplication {
      name = "agent-dms-fetchmail";
      runtimeInputs = [pkgs.coreutils pkgs.fetchmail];
      text = ''
        password="$(tr -d '\n' < "$CREDENTIALS_DIRECTORY/${fastmailCredential}")"
        # Fastmail app passwords are alphanumeric; anything else would need
        # fetchmailrc escaping.
        if [[ ! "$password" =~ ^[A-Za-z0-9]+$ ]]; then
          echo "agent-dms-fetchmail: ${fastmailCredential} is not a plain alphanumeric app password" >&2
          exit 1
        fi
        rc="$RUNTIME_DIRECTORY/fetchmailrc"
        (umask 077 && cat > "$rc" <<EOF
        set daemon 300
        set no bouncemail
        set softbounce
        set postmaster "gio"
        poll imap.fastmail.com protocol imap port 993
          envelope "X-Delivered-to"
          localdomains ${domain}
          no dns
          user "giodamelio@fastmail.com" password "$password" is * here
          folder "AgentDMs"
          ssl sslcertck sslcertfile /etc/ssl/certs/ca-certificates.crt
          idle
          lmtp smtphost 127.0.0.1/${toString lmtpPort}
          smtpaddress ${domain}
        EOF
        )
        exec fetchmail --nodetach --nosyslog -f "$rc"
      '';
    };
  in {
    users.users.stalwart = {
      isSystemUser = true;
      group = "stalwart";
    };
    users.groups.stalwart = {};

    services.postgresql = {
      ensureDatabases = ["stalwart"];
      ensureUsers = [
        {
          name = "stalwart";
          ensureDBOwnership = true;
        }
      ];
      identMap = lib.mkAfter ''
        stalwart root stalwart
        stalwart stalwart stalwart
      '';
      authentication = lib.mkAfter ''
        local all stalwart peer map=stalwart
      '';
    };

    systemd.services.stalwart = {
      description = "Stalwart mail server for agent-dms";
      wantedBy = ["multi-user.target"];
      # ensureUsers creates the role in postgresql-setup, not postgresql.
      after = ["network-online.target" "postgresql-setup.service"];
      wants = ["network-online.target"];
      requires = ["postgresql-setup.service"];
      environment.STALWART_PUBLIC_URL = "https://${domain}";
      serviceConfig = {
        ExecStart = lib.getExe start;
        User = "stalwart";
        Group = "stalwart";
        StateDirectory = "stalwart";
        StateDirectoryMode = "0700";
        # The default Log tracer writes here.
        LogsDirectory = "stalwart";
        # Caddy's token under its own credstore name: Stalwart does its own
        # DNS-01 for the IMAP and submission certificate.
        LoadCredentialEncrypted = ["caddy_cloudflare_api_token"];
        Restart = "on-failure";
        RestartSec = 5;
        KillMode = "process";
        KillSignal = "SIGINT";
        LimitNOFILE = 65536;

        AmbientCapabilities = ["CAP_NET_BIND_SERVICE"];
        CapabilityBoundingSet = ["CAP_NET_BIND_SERVICE"];
        DeviceAllow = [""];
        LockPersonality = true;
        MemoryDenyWriteExecute = true;
        NoNewPrivileges = true;
        PrivateDevices = true;
        PrivateTmp = true;
        ProcSubset = "pid";
        ProtectClock = true;
        ProtectControlGroups = true;
        ProtectHome = true;
        ProtectHostname = true;
        ProtectKernelLogs = true;
        ProtectKernelModules = true;
        ProtectKernelTunables = true;
        ProtectProc = "invisible";
        ProtectSystem = "strict";
        RestrictAddressFamilies = ["AF_INET" "AF_INET6" "AF_UNIX"];
        RestrictNamespaces = true;
        RestrictRealtime = true;
        RestrictSUIDSGID = true;
        SystemCallArchitectures = "native";
        SystemCallFilter = ["@system-service" "~@privileged"];
        UMask = "0077";
      };
    };

    systemd.services.stalwart-apply = {
      description = "Apply the declarative agent-dms Stalwart settings";
      wantedBy = ["multi-user.target"];
      after = ["stalwart.service"];
      requires = ["stalwart.service"];
      # Retries until the server is answering.
      startLimitIntervalSec = 0;
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = lib.getExe apply;
        Restart = "on-failure";
        RestartSec = "10s";
        User = "stalwart";
        Group = "stalwart";
        # stalwart-cli caches the server's schema under $XDG_CACHE_HOME.
        CacheDirectory = "stalwart-cli";
        Environment = "XDG_CACHE_HOME=/var/cache/stalwart-cli";
      };
    };

    fleet.credentials.needs = [fastmailCredential];

    systemd.services.agent-dms-fetchmail = {
      description = "Pull agent-dms mail from Fastmail into Stalwart";
      wantedBy = ["multi-user.target"];
      after = ["network-online.target" "stalwart-apply.service"];
      wants = ["network-online.target"];
      requires = ["stalwart-apply.service"];
      environment.HOME = "/var/lib/agent-dms-fetchmail";
      serviceConfig = {
        ExecStart = lib.getExe fetchmailStart;
        DynamicUser = true;
        StateDirectory = "agent-dms-fetchmail";
        RuntimeDirectory = "agent-dms-fetchmail";
        RuntimeDirectoryMode = "0700";
        LoadCredentialEncrypted = [fastmailCredential];
        Restart = "always";
        RestartSec = 30;

        CapabilityBoundingSet = [""];
        LockPersonality = true;
        MemoryDenyWriteExecute = true;
        NoNewPrivileges = true;
        PrivateDevices = true;
        PrivateTmp = true;
        ProtectClock = true;
        ProtectControlGroups = true;
        ProtectHome = true;
        ProtectHostname = true;
        ProtectKernelLogs = true;
        ProtectKernelModules = true;
        ProtectKernelTunables = true;
        ProtectProc = "invisible";
        ProtectSystem = "strict";
        RestrictAddressFamilies = ["AF_INET" "AF_INET6" "AF_UNIX"];
        RestrictNamespaces = true;
        RestrictRealtime = true;
        SystemCallArchitectures = "native";
        SystemCallFilter = ["@system-service" "~@privileged"];
        UMask = "0077";
      };
    };

    environment.systemPackages = [pkgs.stalwart-cli];

    networking.firewall.allowedTCPPorts = [
      465 # SMTP submission, implicit TLS
      993 # IMAPS
    ];
  };

  den.hosts.x86_64-linux.carbon.services.agent-dms = {
    endpoint = {
      domain = "agent-dms";
      backend.host = "127.0.0.1";
      backend.port = httpPort;
    };
    healthcheck.target = "https://${domain}/healthz/ready";
  };
}
