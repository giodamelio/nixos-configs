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
            type = types.str;
            description = "The upstream host to proxy to";
            example = "localhost";
          };

          port = mkOption {
            type = types.int;
            description = "The upstream port to proxy to";
            example = 8080;
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
        }
      '';
    };
  };

  config = lib.mkIf config.services.gio.reverse-proxy.enable {
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

                reverse_proxy ${cfg.host}:${toString cfg.port}
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
