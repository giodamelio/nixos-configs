{lib, ...}: let
  inherit (lib) mkOption mkIf mkDefault types;

  # Every facet is expressible two ways: a singular sugar option that folds into
  # `<plural>.default`, and the plural attrset consumers actually read. One
  # helper builds both + the fold, so the whole registry is uniform.
  mkFacet = {
    singular,
    plural,
    elemType,
    pluralDesc,
  }: {config, ...}: {
    options.${singular} = mkOption {
      type = types.nullOr elemType;
      default = null;
      description = "A single ${singular}; folded into `${plural}.default`. Consumers read only `${plural}`.";
    };
    options.${plural} = mkOption {
      type = types.attrsOf elemType;
      default = {};
      description = pluralDesc;
    };
    config.${plural} = mkIf (config.${singular} != null) {default = config.${singular};};
  };
in {
  den.schema.host.imports = [
    {
      options.services = mkOption {
        default = {};
        description = ''
          Per-host service registry. Declare a service once, beside the host
          that runs it; consumers render fleet-wide by reading config.den.hosts.
          Each facet is an attrset (plural) with singular sugar for the common
          single-instance case.
        '';
        type = types.attrsOf (types.submodule ({name, ...}: let
          # endpoint — the raw exposure fact. domain defaults to the service name.
          endpointType = types.submodule ({config, ...}: {
            options = {
              domain = mkOption {
                type = types.str;
                default = name;
                defaultText = lib.literalExpression "<service name>";
                description = "Subdomain label under the fleet zone (a leading * is a wildcard).";
              };
              backend.host = mkOption {
                type = types.nullOr types.str;
                default = null;
                description = "Upstream host (null = the owning host).";
              };
              backend.port = mkOption {
                type = types.nullOr types.int;
                default = null;
                description = "Upstream TCP port.";
              };
              backend.socket = mkOption {
                type = types.nullOr types.str;
                default = null;
                description = "Upstream unix socket path (instead of host:port).";
              };
              port = mkOption {
                type = types.int;
                default = 443;
                description = "Public port the reverse proxy listens on.";
              };
              proxy = mkOption {
                type = types.bool;
                defaultText = lib.literalExpression "backend is set";
                description = "Emit a reverse-proxy vhost. Defaults true when a backend is set, false for DNS-only.";
              };
              mtls = mkOption {
                type = types.bool;
                default = false;
                description = "Require client-certificate (mTLS) verification.";
              };
              extraConfig = mkOption {
                type = types.lines;
                default = "";
                description = "Raw Caddy directives appended to the vhost (escape hatch).";
              };
            };
            config.proxy = mkDefault (config.backend.host != null || config.backend.port != null || config.backend.socket != null);
          });

          # healthcheck — what to check + what a good response looks like.
          # gatus and consul are both generators derived from this.
          healthcheckType = types.submodule {
            options = {
              protocol = mkOption {
                type = types.enum ["http" "https" "tcp" "icmp"];
                default = "https";
                description = "Probe protocol.";
              };
              target = mkOption {
                type = types.str;
                description = "URL (http/s), host:port (tcp), or host (icmp).";
              };
              method = mkOption {
                type = types.str;
                default = "GET";
                description = "HTTP method (http/s only).";
              };
              interval = mkOption {
                type = types.str;
                default = "60s";
                description = "Check interval.";
              };
              expect = {
                status = mkOption {
                  type = types.listOf types.int;
                  default = [200];
                  description = "Acceptable HTTP status codes.";
                };
                bodyContains = mkOption {
                  type = types.nullOr types.str;
                  default = null;
                  description = "Substring the body must contain.";
                };
                maxResponseTime = mkOption {
                  type = types.nullOr types.str;
                  default = null;
                  description = "Max acceptable response time, e.g. \"500ms\".";
                };
                tlsValid = mkOption {
                  type = types.nullOr types.bool;
                  default = null;
                  description = "Require a valid TLS certificate (https).";
                };
              };
            };
          };

          # prometheus-endpoint — "exposes Prometheus metrics here". job defaults
          # to the service name.
          prometheusEndpointType = types.submodule {
            options = {
              target = mkOption {
                type = types.str;
                description = "Scrape target, e.g. \"localhost:9090\" or \"immich.gio.ninja\".";
              };
              scheme = mkOption {
                type = types.enum ["http" "https"];
                default = "http";
                description = "Scrape scheme.";
              };
              path = mkOption {
                type = types.str;
                default = "/metrics";
                description = "Metrics path.";
              };
              job = mkOption {
                type = types.str;
                default = name;
                defaultText = lib.literalExpression "<service name>";
                description = "Prometheus job name.";
              };
              labels = mkOption {
                type = types.attrsOf types.str;
                default = {};
                description = "Static labels attached to the job.";
              };
              params = mkOption {
                type = types.attrsOf (types.listOf types.str);
                default = {};
                description = "Query parameters, e.g. { format = [\"prometheus\"]; }.";
              };
              auth = mkOption {
                type = types.nullOr (types.submodule {
                  options = {
                    credentialsFile = mkOption {
                      type = types.nullOr types.str;
                      default = null;
                      description = "Path to a file holding the bearer token.";
                    };
                    credentials = mkOption {
                      type = types.nullOr types.str;
                      default = null;
                      description = "Inline bearer token (prefer credentialsFile).";
                    };
                  };
                });
                default = null;
                description = "Bearer authorization for the scrape, if any.";
              };
            };
          };

          # dashboard — a homer tile. title defaults to the service name.
          dashboardType = types.submodule {
            options = {
              category = mkOption {
                type = types.str;
                description = "Dashboard group, e.g. \"Services\" / \"Media\" / \"Admin\".";
              };
              title = mkOption {
                type = types.str;
                default = name;
                defaultText = lib.literalExpression "<service name>";
                description = "Tile title.";
              };
              subtitle = mkOption {
                type = types.nullOr types.str;
                default = null;
                description = "Tile subtitle.";
              };
              logo = mkOption {
                type = types.nullOr types.str;
                default = null;
                description = "Icon URL.";
              };
              url = mkOption {
                type = types.str;
                description = "Full URL the tile links to.";
              };
            };
          };

          # consul — service registration. Checks are NOT declared here; they are
          # derived from the healthcheck facet by the consul generator.
          consulType = types.submodule {
            options = {
              name = mkOption {
                type = types.str;
                default = name;
                defaultText = lib.literalExpression "<service name>";
                description = "Consul service name.";
              };
              address = mkOption {
                type = types.str;
                default = "${name}.gio.ninja";
                defaultText = lib.literalExpression "<service name>.gio.ninja";
                description = "Registered address (FQDN or IP).";
              };
              port = mkOption {
                type = types.int;
                default = 443;
                description = "Registered port.";
              };
            };
          };
        in {
          imports = [
            (mkFacet {
              singular = "endpoint";
              plural = "endpoints";
              elemType = endpointType;
              pluralDesc = "Network exposures (reverse-proxy vhost + DNS record).";
            })
            (mkFacet {
              singular = "healthcheck";
              plural = "healthchecks";
              elemType = healthcheckType;
              pluralDesc = "Health checks (drive gatus + consul).";
            })
            (mkFacet {
              singular = "prometheus-endpoint";
              plural = "prometheus-endpoints";
              elemType = prometheusEndpointType;
              pluralDesc = "Prometheus scrape endpoints.";
            })
            (mkFacet {
              singular = "dashboard";
              plural = "dashboards";
              elemType = dashboardType;
              pluralDesc = "Homer dashboard tiles.";
            })
            (mkFacet {
              singular = "consul";
              plural = "consuls";
              elemType = consulType;
              pluralDesc = "Consul service registrations.";
            })
          ];

          options.description = mkOption {
            type = types.str;
            default = "";
            description = "Human-readable description of the service.";
          };

          options.unit = mkOption {
            type = types.str;
            default = name;
            defaultText = lib.literalExpression "<service name>";
            description = "systemd unit (without .service) this service runs as.";
          };

          options.mounts = mkOption {
            type = types.listOf types.str;
            default = [];
            description = ''
              fleet.nfs mount names this service needs before it starts. The
              nfs-wait bridge orders `unit` after each mount's readiness target.
            '';
          };
        }));
      };
    }
  ];
}
