# bifrost — the guarded internet entry point (docs/bifrost.md): its own Caddy
# instance built with the bifrost plugin, a wildcard site for gio.bifrost.domain,
# and a fail2ban jail fed by the plugin's failure log.
_: {
  den.aspects.bifrost.nixos = {
    config,
    lib,
    perSystem,
    ...
  }: let
    inherit (lib) mkOption types;
    cfg = config.gio.bifrost;

    unit = "caddy-bifrost";
    credentialDir = "/run/credentials/${unit}.service";
    credential = name: "${credentialDir}/${name}";
    cloudflareToken = "{file.${credential cfg.cloudflareCredential}}";

    authHost = "auth.${cfg.domain}";
    labels = lib.splitString "." cfg.domain;
    ddnsRecord = lib.head labels;
    ddnsZone = lib.concatStringsSep "." (lib.tail labels);

    # {client_ip}, not {remote_host}: LAN traffic arrives through the internal
    # Caddy on loopback, and client_ip follows its X-Forwarded-For.
    rateLimit = zone: events: ''
      rate_limit {
        zone ${zone} {
          key {client_ip}
          events ${toString events}
          window 1m
        }
      }
    '';

    serviceBlock = name: svc: ''
      @${name} host ${name}.${cfg.domain}
      handle @${name} {
        route {
          ${rateLimit name svc.rateLimit}
          ${lib.optionalString (svc.oauth != null) ''
        bifrost_guard oauth {
          host ${name}.${cfg.domain}
          ${lib.optionalString (svc.oauth.scopes != []) "scopes ${toString svc.oauth.scopes}"}
          ${lib.optionalString (svc.oauth.require != []) "require ${toString svc.oauth.require}"}
          ${
          if svc.oauth.groups == []
          then "any_group"
          else "groups ${toString svc.oauth.groups}"
        }
        }
      ''}
          ${svc.config}
          ${lib.optionalString (svc.nats != null) ''
        bifrost_nats {
          subject ${svc.nats.subject}
          ${lib.optionalString (svc.nats.stream != null) "jetstream"}
          ${lib.optionalString (svc.nats.maxBody != null) "max_body ${toString svc.nats.maxBody}"}
        }
      ''}
        }
      }
    '';

    streams = config.gio.nats.streams or {};

    # NATS subject matching, with a Caddy placeholder token standing for any
    # single token: only `*` or `>` in the stream can be sure to cover it.
    subjectCovered = pattern: subject: let
      go = p: s:
        if p == []
        then s == []
        else if lib.head p == ">"
        then s != []
        else if s == []
        then false
        else let
          pt = lib.head p;
          st = lib.head s;
        in
          (pt == "*" || (pt == st && !lib.hasInfix "{" st)) && go (lib.tail p) (lib.tail s);
    in
      go (lib.splitString "." pattern) (lib.splitString "." subject);

    natsAssertions = lib.concatLists (lib.mapAttrsToList (name: svc:
      lib.optionals (svc.nats != null) ([
          {
            assertion = cfg.nats.url != null;
            message = "gio.bifrost.services.${name}.nats needs gio.bifrost.nats.url.";
          }
        ]
        ++ lib.optionals (svc.nats.stream != null) [
          {
            assertion = streams ? ${svc.nats.stream};
            message = "gio.bifrost.services.${name}.nats.stream: ${svc.nats.stream} is not declared in gio.nats.streams on this host.";
          }
          {
            assertion = lib.any (p: subjectCovered p svc.nats.subject) (streams.${svc.nats.stream}.subjects or []);
            message = "gio.bifrost.services.${name}.nats.subject: ${svc.nats.subject} is not covered by stream ${svc.nats.stream}'s subjects.";
          }
        ]))
    cfg.services);

    adminPaths = "/admin /admin/*";

    credentials = lib.unique (
      [cfg.tokenKeyCredential cfg.login.clientSecretCredential]
      ++ lib.optional (cfg.dynamicDns || lib.hasInfix cloudflareToken cfg.tls) cfg.cloudflareCredential
      ++ lib.optional (cfg.nats.credsCredential != null) cfg.nats.credsCredential
      ++ lib.optional (cfg.nats.tokenCredential != null) cfg.nats.tokenCredential
      ++ cfg.credentials
    );
  in {
    options.gio.bifrost = {
      domain = mkOption {
        type = types.str;
        default = "external.gio.ninja";
        description = "Every public service is <name>.<domain>; auth.<domain> is bifrost itself.";
      };

      port = mkOption {
        type = types.port;
        default = 52793;
        description = "HTTPS port the gateway forwards public 443 to.";
      };

      httpPort = mkOption {
        type = types.port;
        default = 52792;
        description = "Never forwarded or opened; set only so it can't collide with another Caddy's :80.";
      };

      tls = mkOption {
        type = types.lines;
        default = ''
          tls {
            dns cloudflare ${cloudflareToken}
            resolvers 1.1.1.1
          }
        '';
        defaultText = "A wildcard certificate via Cloudflare DNS-01, checked against public resolvers.";
        description = "The wildcard site's tls directive. VM tests use `tls internal`.";
      };

      lanProxy = mkOption {
        type = types.bool;
        default = true;
        description = ''
          Serve *.<domain> on the internal Caddy's :443 as well, proxied to
          bifrost over loopback. The fleet DNS points *.<domain> at this host,
          and LAN clients connect to 443, not bifrost's port.
        '';
      };

      dynamicDns = mkOption {
        type = types.bool;
        default = true;
        description = "Keep <domain>'s A record pointed at this host's public IPv4.";
      };

      cloudflareCredential = mkOption {
        type = types.str;
        default = "caddy_cloudflare_api_token";
        description = "Credential holding the Cloudflare token for DNS-01 and dynamic DNS.";
      };

      tokenKeyCredential = mkOption {
        type = types.str;
        default = "bifrost_token_key";
        description = "Credential holding fosite's HMAC key (at least 32 bytes).";
      };

      login = {
        issuer = mkOption {
          type = types.str;
          default = "https://login.gio.ninja";
          description = "The OIDC provider whose login approves every grant.";
        };
        clientId = mkOption {
          type = types.str;
          description = "bifrost's client ID at the OIDC provider.";
        };
        clientSecretCredential = mkOption {
          type = types.str;
          default = "bifrost_pocket_id_client_secret";
          description = "Credential holding bifrost's client secret at the OIDC provider.";
        };
        maxAuthAge = mkOption {
          type = types.str;
          default = "5m";
          description = "How old a login may be when it reaches the consent screen.";
        };
        allowedGroups = mkOption {
          type = types.listOf types.str;
          default = ["bifrost"];
          description = "The provider's groups allowed to approve grants. Empty allows any account.";
        };
      };

      adminNetworks = mkOption {
        type = types.listOf types.str;
        default = ["10.0.0.0/8"];
        description = "Source ranges /admin answers to.";
      };

      authRateLimit = mkOption {
        type = types.ints.positive;
        default = 60;
        description = "Requests per minute per address to the OAuth endpoints.";
      };

      adminRateLimit = mkOption {
        type = types.ints.positive;
        default = 120;
        description = "Requests per minute per address to /admin.";
      };

      nats = {
        url = mkOption {
          type = types.nullOr types.str;
          default = null;
          example = "nats://127.0.0.1:4222";
          description = "NATS server that `bifrost_nats` handlers publish to. null leaves NATS off.";
        };
        credsCredential = mkOption {
          type = types.nullOr types.str;
          default = null;
          description = "Credential holding a NATS .creds file, if the server requires one.";
        };
        tokenCredential = mkOption {
          type = types.nullOr types.str;
          default = null;
          description = "Credential holding a NATS token, if the server requires one.";
        };
      };

      credentials = mkOption {
        type = types.listOf types.str;
        default = [];
        description = "Extra credentials service snippets read, at `credentialDir`/<name>.";
      };

      credentialDir = mkOption {
        type = types.str;
        readOnly = true;
        default = credentialDir;
        description = "Where the instance's credentials appear at runtime.";
      };

      services = mkOption {
        default = {};
        description = "Public services, each served at <name>.<domain>.";
        type = types.attrsOf (types.submodule {
          options = {
            rateLimit = mkOption {
              type = types.ints.positive;
              default = 1200;
              description = "Requests per minute per address.";
            };
            oauth = mkOption {
              default = null;
              description = "Guard the whole service with bifrost OAuth tokens.";
              type = types.nullOr (types.submodule {
                options = {
                  scopes = mkOption {
                    type = types.listOf types.str;
                    default = [];
                    description = "Scopes this resource offers.";
                  };
                  require = mkOption {
                    type = types.listOf types.str;
                    default = [];
                    description = "Scopes every request must have been granted.";
                  };
                  # No default, so a new service is never open to every account by accident.
                  groups = mkOption {
                    type = types.listOf types.str;
                    example = ["family"];
                    description = ''
                      Pocket ID groups allowed to use the service; membership in any one
                      is enough. [] admits every account that can log in to bifrost
                      (login.allowedGroups). Checked at consent and on every request,
                      against the groups recorded when the grant was approved.
                    '';
                  };
                };
              });
            };
            config = mkOption {
              type = types.lines;
              default = "";
              description = "Caddyfile handlers inside the service's route, after the rate limit and any oauth guard.";
            };
            nats = mkOption {
              default = null;
              description = "Publish every request that gets past `config` to NATS, as bifrost_nats.";
              type = types.nullOr (types.submodule {
                options = {
                  subject = mkOption {
                    type = types.str;
                    example = "webhooks.github";
                    description = "May use Caddy placeholders.";
                  };
                  stream = mkOption {
                    type = types.nullOr types.str;
                    default = null;
                    description = ''
                      A gio.nats.streams name on this host. Set, bifrost publishes
                      through JetStream, and evaluation checks the stream covers
                      the subject. null publishes on core NATS.
                    '';
                  };
                  maxBody = mkOption {
                    type = types.nullOr types.ints.positive;
                    default = null;
                    description = "Largest body accepted, in bytes. null keeps bifrost's default.";
                  };
                };
              });
            };
          };
        });
      };

      fail2ban = {
        maxRetry = mkOption {
          type = types.ints.positive;
          default = 50;
          description = "Failures within findTime that ban an address.";
        };
        findTime = mkOption {
          type = types.str;
          default = "10m";
        };
        banTime = mkOption {
          type = types.str;
          default = "1h";
        };
        ignoreIP = mkOption {
          type = types.listOf types.str;
          default = ["10.0.0.0/8" "fd00::/8"];
          description = "Never banned: the LAN and VPN.";
        };
      };
    };

    config = {
      assertions =
        natsAssertions
        ++ [
          {
            assertion = !(cfg.services ? auth);
            message = "gio.bifrost.services: `auth` is reserved for bifrost's own authorization server.";
          }
          {
            assertion = cfg.lanProxy -> lib.hasSuffix ".gio.ninja" cfg.domain;
            message = "gio.bifrost.lanProxy: the internal reverse proxy only serves names under gio.ninja.";
          }
        ];

      services.gio.reverse-proxy = lib.mkIf cfg.lanProxy {
        enable = true;
        virtualHosts.bifrost-lan = {
          domain = "*.${lib.removeSuffix ".gio.ninja" cfg.domain}";
          reverseProxy = false;
          extraConfig = ''
            reverse_proxy https://127.0.0.1:${toString cfg.port} {
              # An HTTPS upstream otherwise gets Host: 127.0.0.1:<port>, which
              # matches none of bifrost's routes.
              header_up Host {host}
              transport http {
                tls_server_name auth.${cfg.domain}
              }
              stream_close_delay 10m
            }
          '';
        };
      };

      users.users.bifrost = {
        isSystemUser = true;
        group = "bifrost";
      };
      users.groups.bifrost = {};

      gio.caddy.instances.bifrost = {
        package = perSystem.self.bifrost;
        user = "bifrost";
        group = "bifrost";
        dataDir = "/var/lib/bifrost";
        inherit (cfg) httpPort;
        httpsPort = cfg.port;
        email = "admin@gio.ninja";
        # Failures log at WARN for fail2ban; grant events at INFO.
        logFormat = "level INFO\n";
        globalConfig = ''
          auto_https disable_redirects

          # Only the internal Caddy's LAN proxy connects from loopback; internet
          # clients can't, so they can't set their own X-Forwarded-For.
          servers {
            trusted_proxies static 127.0.0.1/32 ::1/128
            client_ip_headers X-Forwarded-For
          }

          bifrost {
            issuer https://${authHost}
            login {
              oidc_issuer ${cfg.login.issuer}
              client_id ${cfg.login.clientId}
              client_secret_file ${credential cfg.login.clientSecretCredential}
              max_auth_age ${cfg.login.maxAuthAge}
              ${lib.optionalString (cfg.login.allowedGroups != []) "allowed_groups ${toString cfg.login.allowedGroups}"}
            }
            token_key_file ${credential cfg.tokenKeyCredential}
            ${lib.optionalString (cfg.nats.url != null) ''
            nats {
              url ${cfg.nats.url}
              ${lib.optionalString (cfg.nats.credsCredential != null) "creds_file ${credential cfg.nats.credsCredential}"}
              ${lib.optionalString (cfg.nats.tokenCredential != null) "token_file ${credential cfg.nats.tokenCredential}"}
            }
          ''}
          }

          ${lib.optionalString cfg.dynamicDns ''
            dynamic_dns {
              provider cloudflare ${cloudflareToken}
              domains {
                ${ddnsZone} ${ddnsRecord}
              }
              versions ipv4
            }
          ''}
        '';
        extraConfig = ''
          *.${cfg.domain} {
            ${cfg.tls}

            @auth host ${authHost}
            handle @auth {
              route {
                @admin path ${adminPaths}
                @oauth not path ${adminPaths}
                rate_limit @admin {
                  zone admin {
                    key {client_ip}
                    events ${toString cfg.adminRateLimit}
                    window 1m
                  }
                }
                rate_limit @oauth {
                  zone auth {
                    key {client_ip}
                    events ${toString cfg.authRateLimit}
                    window 1m
                  }
                }
                bifrost_authserver {
                  admin_networks ${toString cfg.adminNetworks}
                }
              }
            }

            ${lib.concatStrings (lib.mapAttrsToList serviceBlock cfg.services)}

            handle {
              bifrost_reject
            }
          }
        '';
      };

      fleet.credentials.needs = credentials;

      systemd.services.${unit}.serviceConfig.LoadCredentialEncrypted = credentials;

      networking.firewall.allowedTCPPorts = [cfg.port];

      services.fail2ban = {
        enable = true;
        inherit (cfg.fail2ban) ignoreIP;
        jails.bifrost = {
          # Matches the plugin's FailureMessage line; remote_ip is the first field.
          filter.Definition = {
            failregex = ''"msg":"bifrost check failed","remote_ip":"<HOST>"'';
            ignoreregex = "";
          };
          settings = {
            backend = "systemd";
            journalmatch = "_SYSTEMD_UNIT=${unit}.service";
            port = toString cfg.port;
            maxretry = cfg.fail2ban.maxRetry;
            findtime = cfg.fail2ban.findTime;
            bantime = cfg.fail2ban.banTime;
          };
        };
      };
    };
  };
}
