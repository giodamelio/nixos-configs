{
  pkgs,
  lib,
  config,
  ...
}: {
  options.services.gio.reverse-proxy = with lib; {
    enable = mkEnableOption "Caddy reverse proxy service";

    virtualHosts = mkOption {
      type = types.attrsOf (types.submodule {
        options = {
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

          reverseProxy = mkOption {
            type = types.bool;
            default = true;
            description = "Automatically configure reverse_proxy directive";
          };

          extraConfig = mkOption {
            type = types.lines;
            default = "";
          };
        };
      });
      default = {};
      description = "Virtual hosts configuration for the reverse proxy";
      example = literalExpression ''
        {
          "example" = {
            host = "localhost";
            port = 8080;
          };
          "api" = {
            host = "127.0.0.1";
            port = 3000;
          };
          "openbao" = {
            socket_path = "/run/openbao/openbao.sock";
          };
        }
      '';
    };
  };

  config = lib.mkIf config.services.gio.reverse-proxy.enable {
    assertions = lib.flatten (
      lib.mapAttrsToList (
        hostname: cfg: {
          assertion = (cfg.socket_path != null) != (cfg.host != null && cfg.port != null);
          message = "Virtual host '${hostname}' must specify either socket_path OR both host and port";
        }
      )
      config.services.gio.reverse-proxy.virtualHosts
    );

    # Setup Caddy as a reverse proxy
    systemd.services.caddy.serviceConfig = {
      LoadCredentialEncrypted = [
        "caddy-cloudflare-api-token"
      ];
      Environment = [
        "CLOUDFLARE_API_TOKEN_FILE=%d/caddy-cloudflare-api-token"
      ];
    };
    services.caddy = {
      enable = true;

      package = pkgs.caddy.withPlugins {
        plugins = [
          "github.com/caddy-dns/cloudflare@v0.2.1"
        ];
        hash = "sha256-iRzpN9awuEFsc7hqKzOMNiCFFEv833xhd4LM+VFQedI=";
      };

      globalConfig = ''
        email admin@gio.ninja
      '';

      virtualHosts =
        lib.mapAttrs' (
          hostname: cfg:
            lib.nameValuePair "https://${hostname}.gio.ninja" {
              extraConfig = ''
                tls {
                  dns cloudflare {file.{$CLOUDFLARE_API_TOKEN_FILE}}
                  resolvers 1.1.1.1
                }

                ${cfg.extraConfig}

                ${
                  lib.optionalString cfg.reverseProxy (
                    if cfg.socket_path != null
                    then "reverse_proxy unix/${cfg.socket_path}"
                    else "reverse_proxy ${cfg.host}:${toString cfg.port}"
                  )
                }
              '';
            }
        )
        config.services.gio.reverse-proxy.virtualHosts;
    };

    networking.firewall.allowedTCPPorts = [
      80
      443
    ];
  };
}
