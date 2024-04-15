{root, ...}: {
  pkgs,
  config,
  ...
}: let
  caddyDnsCloudflare = root.packages.caddy-dns-cloudflare {inherit pkgs;};
in {
  # Cloudflare Token Secret
  age.secrets.cloudflare-token.file = ../../../secrets/cloudflare-token.age;

  services.caddy = {
    enable = true;
    package = caddyDnsCloudflare;

    globalConfig = ''
      email admin@gio.ninja
      acme_dns cloudflare {env.CLOUDFLARE_API_TOKEN}
    '';
  };

  systemd.services.caddy = {
    serviceConfig = {
      # I don't understand how Caddy is ever working without this...
      AmbientCapabilities = "CAP_NET_BIND_SERVICE";

      # Work around to load credendial from age into caddy env var
      LoadCredential = "CLOUDFLARE_API_TOKEN:${config.age.secrets.cloudflare-token.path}";
      EnvironmentFile = "-%t/caddy/secrets.env";
      RuntimeDirectory = "caddy";
      ExecStartPre = [
        ((pkgs.writeShellApplication {
            name = "caddy-secrets";
            text = ''
              echo "CLOUDFLARE_API_TOKEN=$(<"$CREDENTIALS_DIRECTORY/CLOUDFLARE_API_TOKEN")" > "$RUNTIME_DIRECTORY/secrets.env"
            '';
          })
          + "/bin/caddy-secrets")
      ];
    };
  };

  networking.firewall.interfaces."wg0" = {
    allowedTCPPorts = [443 80];
  };
  networking.firewall.interfaces."wg9" = {
    allowedTCPPorts = [443 80];
  };
}
