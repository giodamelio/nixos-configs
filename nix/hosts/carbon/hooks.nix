{
  config,
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
      # GitHub App webhooks for the private Gradient instance. GitHub delivers
      # to https://hooks.gio.ninja:47291/<id>; we forward verbatim to Gradient,
      # which verifies the X-Hub-Signature-256 HMAC itself. No [hook.auth] here:
      # GitHub signs the body rather than sending a static shared-secret header.
      {
        id = "cf7ccf08-2541-49eb-903b-e7cd59dd10f2";
        verify = [
          {
            type = "hmac";
            header = "X-Hub-Signature-256";
            secret_file = "/run/credentials/webhookcatcher.service/gradient_github_app_webhook_secret";
          }
        ];
        actions.forward.url = "http://127.0.0.1:3002/api/v1/hooks/github";
      }
      # Gradient deploy webhook → gradient-deployer Restate service. Gradient's
      # send_web_request can't target the loopback ingress directly (its SSRF
      # guard blocks IP literals), so it posts here (a hostname) with a bearer;
      # we verify it and forward to the local Restate ingress, which durably
      # invokes the yesman slot's Reconcile handler.
      {
        id = "gradient-deploy-yesman";
        verify = [
          {
            type = "bearer";
            header = "Authorization";
            secret_file = "/run/credentials/webhookcatcher.service/gradient_action_deploy-webhook_token";
          }
        ];
        actions.forward.url = "${config.gio.restate.ingressEndpoint}/gradient-deployer-carbon/yesman/Reconcile";
      }
      # Same as the yesman deploy webhook, for the eater-of-feeds slot. Reuses
      # the shared deploy-webhook bearer; routing to the right slot is by URL.
      {
        id = "gradient-deploy-eater-of-feeds";
        verify = [
          {
            type = "bearer";
            header = "Authorization";
            secret_file = "/run/credentials/webhookcatcher.service/gradient_action_deploy-webhook_token";
          }
        ];
        actions.forward.url = "${config.gio.restate.ingressEndpoint}/gradient-deployer-carbon/eater-of-feeds/Reconcile";
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
      # Decrypt the GitHub webhook secret into the unit's credentials dir so
      # the hmac verifier can read it. Same credstore file Gradient uses.
      # gradient_action_deploy-webhook_token is the shared bearer used to
      # authenticate Gradient's deploy webhook (same secret the gradient-server
      # sends).
      LoadCredentialEncrypted = [
        "gradient_github_app_webhook_secret"
        "gradient_action_deploy-webhook_token"
      ];
    };
  };

  networking.firewall.allowedTCPPorts = [47291];

  # # We define the crowdsec tables ourselves so the drop rules are scoped to
  # # port 47291 only. The bouncer's default table names ("crowdsec" / "crowdsec6")
  # # must stay separate — using the same name for both causes a Nix duplicate
  # # attribute error in the bouncer module regardless of createRulesets.
  # networking.nftables.tables."crowdsec" = {
  #   family = "ip";
  #   content = ''
  #     set crowdsec-blacklists {
  #       type ipv4_addr
  #       flags dynamic, timeout
  #     }
  #
  #     chain hook-input {
  #       type filter hook input priority -1
  #       ip saddr @crowdsec-blacklists tcp dport 47291 counter drop
  #     }
  #   '';
  # };
  #
  # networking.nftables.tables."crowdsec6" = {
  #   family = "ip6";
  #   content = ''
  #     set crowdsec6-blacklists {
  #       type ipv6_addr
  #       flags dynamic, timeout
  #     }
  #
  #     chain hook-input {
  #       type filter hook input priority -1
  #       ip6 saddr @crowdsec6-blacklists tcp dport 47291 counter drop
  #     }
  #   '';
  # };
  #
  # services.crowdsec = {
  #   enable = true;
  #   hub.collections = ["crowdsecurity/caddy"];
  #   localConfig.acquisitions = [
  #     {
  #       source = "file";
  #       filenames = ["/var/log/caddy/hooks.gio.ninja.log"];
  #       labels = {
  #         type = "caddy";
  #       };
  #     }
  #   ];
  # };
  #
  # services.crowdsec-firewall-bouncer = {
  #   enable = true;
  #   registerBouncer.enable = true;
  #   createRulesets = lib.mkForce false;
  #   settings = {
  #     mode = "nftables";
  #     nftables = {
  #       ipv4.set-only = true;
  #       ipv6.set-only = true;
  #     };
  #   };
  # };
}
