# grist — spreadsheets (grist.gio.ninja) as a quadlet/podman container with OIDC.
# The three GRIST_* secrets are podman secrets the container references by name;
# they were created out-of-band in Blueprint (not in nix) and remain a manual
# `podman secret create` step on deploy. Converted from nix/hosts/carbon/grist.nix.
{inputs, ...}: {
  den.aspects.carbon.nixos = {
    imports = [
      inputs.quadlet-nix.nixosModules.quadlet
    ];

    config = {
      virtualisation.quadlet.autoEscape = true;
      virtualisation.quadlet.containers.grist = {
        autoStart = true;
        containerConfig = {
          image = "docker.io/gristlabs/grist:latest";
          autoUpdate = "registry";
          networks = ["podman"];
          dns = ["10.88.0.1"];
          volumes = [
            "/var/lib/grist:/persist"
          ];
          publishPorts = [
            "8484:8484"
          ];
          environments = {
            GRIST_DEFAULT_EMAIL = "gio@damelio.net";
            APP_HOME_URL = "https://grist.gio.ninja";

            GRIST_FORCE_LOGIN = "true";

            GRIST_OIDC_SP_HOST = "https://grist.gio.ninja";
            GRIST_OIDC_IDP_ISSUER = "https://login.gio.ninja";
            GRIST_OIDC_IDP_ENABLED_PROTECTIONS = "STATE,NONCE";
            GRIST_OIDC_IDP_SCOPES = "openid email profile";
            GRIST_OIDC_IDP_SKIP_END_SESSION_ENDPOINT = "true";
            GRIST_OIDC_IDP_EXTRA_CLIENT_METADATA = ''{"token_endpoint_auth_method": "client_secret_basic"}'';

            GRIST_LOG_LEVEL = "debug";
            DEBUG = "*";
            NODE_OPTIONS = "--trace-warnings";
          };
          secrets = [
            "grist_session_secret,type=env,target=GRIST_SESSION_SECRET"
            "grist_oidc_idp_client_id,type=env,target=GRIST_OIDC_IDP_CLIENT_ID"
            "grist_oidc_idp_client_secret,type=env,target=GRIST_OIDC_IDP_CLIENT_SECRET"
          ];
        };
      };

      systemd.timers.podman-auto-update.enable = true;
    };
  };

  den.hosts.x86_64-linux.carbon.services.grist = {
    endpoint = {
      domain = "grist";
      backend.host = "localhost";
      backend.port = 8484;
    };
    healthcheck.target = "https://grist.gio.ninja";
  };
}
