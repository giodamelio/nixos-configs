{inputs, ...}: {
  imports = [
    inputs.quadlet-nix.nixosModules.quadlet
  ];

  virtualisation.quadlet.autoEscape = true;
  virtualisation.quadlet.containers.grist = {
    autoStart = true;
    containerConfig = {
      image = "docker.io/gristlabs/grist:1.7";
      networks = ["podman"];
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

        #GRIST_OIDC_IDP_ISSUER = "https://login.gio.ninja/.well-known/openid-configuration";
        GRIST_OIDC_SP_HOST = "https://grist.gio.ninja";
        GRIST_OIDC_IDP_ISSUER = "https://login.gio.ninja";
        GRIST_OIDC_IDP_ENABLED_PROTECTIONS = "STATE,NONCE";
        GRIST_OIDC_IDP_SCOPES = "openid email profile";
        GRIST_OIDC_IDP_SKIP_END_SESSION_ENDPOINT = "true";
        GRIST_OIDC_IDP_EXTRA_CLIENT_METADATA = ''{"token_endpoint_auth_method": "client_secret_basic"}'';

        GRIST_LOG_LEVEL = "debug";
        # DEBUG = "openid-client:*"; # Enable openid-client library debug logs
        DEBUG = "*"; # Enable ALL debug output
        NODE_OPTIONS = "--trace-warnings";
      };
      secrets = [
        "grist_session_secret,type=env,target=GRIST_SESSION_SECRET"
        "grist_oidc_idp_client_id,type=env,target=GRIST_OIDC_IDP_CLIENT_ID"
        "grist_oidc_idp_client_secret,type=env,target=GRIST_OIDC_IDP_CLIENT_SECRET"
      ];
    };
  };

  gio.services.grist.consul = {
    name = "grist";
    address = "grist.gio.ninja";
    port = 443;
    checks = [
      {
        http = "https://grist.gio.ninja";
        interval = "60s";
      }
    ];
  };

  services.gio.reverse-proxy = {
    enable = true;
    virtualHosts = {
      "grist" = {
        host = "localhost";
        port = 8484;
      };
    };
  };
}
