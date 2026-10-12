# hooks — webhookcatcher edge (hooks.gio.ninja:47291) that verifies GitHub App +
# Gradient deploy webhooks and forwards them to Gradient / the Restate ingress.
# Socket-activated; the custom-port TLS vhost is rendered by the den reverse-proxy
# from the fleet endpoint. The two webhook secrets are shared with gradient-server
# (it sends/signs them), so they're declared here with use-sites on both units and
# the legacy underscore credstore names are hyphenated for fleet.secrets.
# Converted from nix/hosts/carbon/hooks.nix.
_: {
  den.aspects.carbon.nixos = {
    config,
    pkgs,
    perSystem,
    ...
  }: let
    webhookcatcher = perSystem.self.webhookcatcher;
    configFile = (pkgs.formats.toml {}).generate "webhookcatcher.toml" {
      hook = [
        {
          id = "print-test";
          actions.print = {};
        }
        {
          id = "cf7ccf08-2541-49eb-903b-e7cd59dd10f2";
          verify = [
            {
              type = "hmac";
              header = "X-Hub-Signature-256";
              secret_file = "/run/credentials/webhookcatcher.service/gradient-github-app-webhook-secret";
            }
          ];
          actions.forward.url = "http://127.0.0.1:3002/api/v1/hooks/github";
        }
        {
          id = "gradient-deploy-yesman";
          verify = [
            {
              type = "bearer";
              header = "Authorization";
              secret_file = "/run/credentials/webhookcatcher.service/gradient-action-deploy-webhook-token";
            }
          ];
          actions.forward.url = "${config.gio.restate.ingressEndpoint}/gradient-deployer-carbon/yesman/Reconcile";
        }
        {
          id = "gradient-deploy-eater-of-feeds";
          verify = [
            {
              type = "bearer";
              header = "Authorization";
              secret_file = "/run/credentials/webhookcatcher.service/gradient-action-deploy-webhook-token";
            }
          ];
          actions.forward.url = "${config.gio.restate.ingressEndpoint}/gradient-deployer-carbon/eater-of-feeds/Reconcile";
        }
      ];
    };
  in {
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
  };

  # Custom-port TLS vhost to the unix socket; no consul (matches Blueprint).
  den.hosts.x86_64-linux.carbon.services.hooks = {
    endpoint = {
      domain = "hooks";
      port = 47291;
      backend.socket = "/run/webhookcatcher.sock";
    };
    consul.enable = false;
  };

  # Shared verification secrets. webhookcatcher reads them from its credential dir
  # (direct path); gradient-server reads them via the underscore-id mapping in
  # gradient.nix (credstore blob), so it needs no use-site here.
  fleet.secrets = {
    gradient-github-app-webhook-secret = {
      origin = "carbon";
      use.carbon.services.webhookcatcher.type = "credential";
    };
    gradient-action-deploy-webhook-token = {
      origin = "carbon";
      use.carbon.services.webhookcatcher.type = "credential";
    };
  };
}
