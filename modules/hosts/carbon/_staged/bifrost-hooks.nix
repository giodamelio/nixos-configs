# Gradient's webhooks on bifrost, replacing hooks.nix. Comes back with the
# gradient/restate wave: it needs gradient-server on :3002 and gio.restate.
_: {
  den.aspects.carbon.nixos = {config, ...}: let
    cred = name: "${config.gio.bifrost.credentialDir}/${name}";
  in {
    gio.bifrost = {
      credentials = [
        "gradient_github_app_webhook_secret"
        "gradient_action_deploy_webhook_token"
      ];

      services = {
        # The GitHub App's webhook URL: https://gradient-hooks.external.gio.ninja/
        gradient-hooks.config = ''
          bifrost_guard hmac {
            header X-Hub-Signature-256
            prefix sha256=
            secret_file ${cred "gradient_github_app_webhook_secret"}
          }
          rewrite * /api/v1/hooks/github
          reverse_proxy 127.0.0.1:3002
        '';

        # Gradient's deploy action posts to https://deploy-hooks.external.gio.ninja/<app>.
        deploy-hooks.config = ''
          bifrost_guard bearer {
            token_file ${cred "gradient_action_deploy_webhook_token"}
          }
          @app path_regexp app ^/(yesman|eater-of-feeds)$
          @app_unknown not path_regexp ^/(yesman|eater-of-feeds)$
          error @app_unknown 404
          rewrite @app /gradient-deployer-carbon/{re.app.1}/Reconcile
          reverse_proxy ${config.gio.restate.ingressEndpoint}
        '';
      };
    };
  };
}
