# reverse-proxy — Caddy reverse proxy with automatic Cloudflare-DNS TLS.
# The single host-level Caddy-shaping layer: fleet.services renders endpoints
# through it, and deployed-apps targets it directly. Converted from
# nix/modules/nixos/reverse-proxy.nix.
_: {
  den.aspects.reverse-proxy.nixos = {
    pkgs,
    lib,
    config,
    ...
  }: {
    options.services.gio.reverse-proxy = with lib; {
      enable = mkEnableOption "Caddy reverse proxy service";

      certIssuer = mkOption {
        type = types.enum ["cloudflare" "internal"];
        default = "cloudflare";
        description = "How HTTPS vhosts get certificates: Cloudflare DNS-01, or Caddy's local CA for VM tests, which cannot reach Cloudflare.";
      };

      virtualHosts = mkOption {
        type = types.attrsOf (types.submodule ({name, ...}: {
          options = {
            domain = mkOption {
              type = types.str;
              default = name;
              defaultText = literalExpression "<attr name>";
              description = "Subdomain label under gio.ninja (a leading * is a wildcard).";
            };

            listenPort = mkOption {
              type = types.int;
              default = 443;
              description = "Public port Caddy serves this vhost on.";
            };

            tls = mkOption {
              type = types.bool;
              default = true;
              description = "Serve HTTPS via Cloudflare-DNS TLS. false = plain HTTP (no credential needed).";
            };

            tlsExtraConfig = mkOption {
              type = types.lines;
              default = "";
              description = "Extra lines inside the vhost's `tls { }` block, e.g. client_auth.";
            };

            host = mkOption {
              type = types.nullOr types.str;
              default = null;
              description = "The upstream host to proxy to";
              example = "localhost";
            };

            port = mkOption {
              type = types.nullOr types.int;
              default = null;
              description = "The upstream port to proxy to";
              example = 8080;
            };

            socket_path = mkOption {
              type = types.nullOr types.str;
              default = null;
              description = "The upstream Unix socket path to proxy to";
              example = "/run/openbao/openbao.sock";
            };

            protocol = mkOption {
              type = types.enum ["http" "h2c"];
              default = "http";
              description = "Upstream transport: http or h2c (HTTP/2 cleartext).";
            };

            reverseProxy = mkOption {
              type = types.bool;
              default = true;
              description = "Emit the automatic reverse_proxy directive. Set false to drive routing entirely from extraConfig.";
            };

            extraConfig = mkOption {
              type = types.lines;
              default = "";
            };
          };
        }));
        default = {};
        description = "Virtual hosts configuration for the reverse proxy";
      };
    };

    config = lib.mkIf config.services.gio.reverse-proxy.enable (let
      vhosts = config.services.gio.reverse-proxy.virtualHosts;
      cred = "caddy_cloudflare_api_token";
      useCloudflare = config.services.gio.reverse-proxy.certIssuer == "cloudflare";

      issuerLines =
        if useCloudflare
        then ["dns cloudflare {file.{$CLOUDFLARE_API_TOKEN_FILE}}" "resolvers 1.1.1.1"]
        else ["issuer internal"];
      tlsLines = cfg: issuerLines ++ lib.optional (cfg.tlsExtraConfig != "") cfg.tlsExtraConfig;

      # A backend is only required when we emit the automatic reverse_proxy; with
      # reverseProxy = false the extraConfig owns routing (file_server, php_fastcgi,
      # custom handles), so no upstream need be set.
      backendTarget = cfg:
        if cfg.socket_path != null
        then "unix/${cfg.socket_path}"
        else "${cfg.host}:${toString cfg.port}";

      proxyDirective = cfg:
        if cfg.protocol == "h2c"
        then ''
          reverse_proxy ${backendTarget cfg} {
            transport http {
              versions h2c
            }
          }
        ''
        else "reverse_proxy ${backendTarget cfg}";

      # Open every distinct public port the vhosts listen on (80/443 + any custom).
      listenPorts = lib.unique (map (cfg: cfg.listenPort) (lib.attrValues vhosts));

      # The Cloudflare token is only needed by HTTPS vhosts. With every vhost on
      # plain HTTP (tls = false) the credential is omitted entirely — so Caddy
      # starts without it (e.g. in VM tests, which have no token).
      anyTls = lib.any (cfg: cfg.tls) (lib.attrValues vhosts);

      scheme = cfg:
        if cfg.tls
        then "https"
        else "http";
      stdPort = cfg:
        if cfg.tls
        then 443
        else 80;
    in {
      assertions =
        lib.mapAttrsToList (hostname: cfg: {
          assertion = !cfg.reverseProxy || ((cfg.socket_path != null) != (cfg.host != null && cfg.port != null));
          message = "reverse-proxy vhost '${hostname}': with reverseProxy = true, set either socket_path OR both host and port";
        })
        vhosts;

      fleet.credentials.needs = lib.mkIf (anyTls && useCloudflare) [cred];

      systemd.services.caddy.serviceConfig = lib.mkIf (anyTls && useCloudflare) {
        LoadCredentialEncrypted = [cred];
        Environment = ["CLOUDFLARE_API_TOKEN_FILE=%d/${cred}"];
      };

      services.caddy = {
        enable = true;

        package = pkgs.caddy.withPlugins {
          plugins = [
            "github.com/caddy-dns/cloudflare@v0.2.1"
            "github.com/relvacode/caddy-oidc@v0.4.3"
            # Last commit before master required Go 1.26.9
            # REMIND-ME-TO: Move caddy-l4 to master or a newer tag nixpkg_version=nixpkgs-unstable:go@>=1.26.9
            "github.com/mholt/caddy-l4@v0.1.3-0.20261029145729-f607ccea1b7d"
            "github.com/gr33nbl00d/caddy-revocation-validator@v1.0.7"
          ];
          hash = "sha256-YWnbo4nx5QgqQz7jtF8AtwM63m5SvclucNokPhcr0ug=";
        };

        globalConfig = ''
          email admin@gio.ninja
        '';

        virtualHosts =
          lib.mapAttrs' (
            _name: cfg: let
              addr = "${scheme cfg}://${cfg.domain}.gio.ninja${lib.optionalString (cfg.listenPort != stdPort cfg) ":${toString cfg.listenPort}"}";
            in
              lib.nameValuePair addr {
                extraConfig = ''
                  ${lib.optionalString cfg.tls ''
                    tls {
                      ${lib.concatStringsSep "\n  " (tlsLines cfg)}
                    }
                  ''}
                  ${cfg.extraConfig}

                  ${lib.optionalString cfg.reverseProxy (proxyDirective cfg)}
                '';
              }
          )
          vhosts;
      };

      networking.firewall.allowedTCPPorts = [80] ++ listenPorts;
    });
  };
}
