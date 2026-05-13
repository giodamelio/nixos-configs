{
  lib,
  pkgs,
  flake,
  ...
}: let
  webhookcatcher = flake.packages.${pkgs.stdenv.hostPlatform.system}.webhookcatcher;
  configFile = (pkgs.formats.toml {}).generate "webhookcatcher.toml" {
    hook = [
      {
        id = "print-test";
        actions.print = {};
      }
    ];
  };
in {
  services.caddy.virtualHosts."https://hooks.gio.ninja:47291" = {
    extraConfig = ''
      log {
        output file /var/log/caddy/hooks.gio.ninja.log
        format json
      }

      tls {
        dns cloudflare {file.{$CLOUDFLARE_API_TOKEN_FILE}}
        resolvers 1.1.1.1
      }

      reverse_proxy unix//run/webhookcatcher.sock
    '';
  };

  systemd.sockets.webhookcatcher = {
    description = "Webhook Catcher Socket";
    wantedBy = ["sockets.target"];
    socketConfig = {
      ListenStream = "/run/webhookcatcher.sock";
      SocketMode = "0666";
    };
  };

  systemd.services.webhookcatcher = {
    description = "Webhook Catcher";
    requires = ["webhookcatcher.socket"];
    after = ["webhookcatcher.socket"];
    serviceConfig = {
      Type = "simple";
      ExecStart = "${webhookcatcher}/bin/webhookcatcher ${configFile}";
      Restart = "on-failure";
      DynamicUser = true;
    };
  };

  networking.firewall.allowedTCPPorts = [47291];
}
