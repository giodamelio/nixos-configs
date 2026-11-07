_: {
  den.aspects.telemetry-cluster.nixos = {
    fleet,
    host,
    lib,
    ...
  }: let
    cfg = fleet.telemetry;
    inherit (cfg) ui;
    credentialsDir = "/run/credentials/caddy.service";
    credentials = {
      clientId = "telemetry_ui_oidc_client_id";
      clientSecret = "telemetry_ui_oidc_client_secret";
      cookieSecret = "telemetry_ui_oidc_cookie_secret";
    };
    credential = name: "{file.${credentialsDir}/${name}}";

    site = port: home: {
      host = "127.0.0.1";
      inherit port;
      extraConfig =
        ''
          import telemetry_ui_oidc
        ''
        + lib.optionalString (home != null) ''
          redir / ${home}
        '';
    };
  in
    lib.mkIf (ui.enable && host.name == ui.host) {
      assertions = [
        {
          assertion = lib.elem ui.host cfg.clusterNodes;
          message = "fleet.telemetry.ui.host (${ui.host}) must be a cluster member: the UIs proxy to its local vmselect, VictoriaLogs and Alertmanager.";
        }
      ];

      fleet.credentials.needs = lib.attrValues credentials;
      systemd.services.caddy.serviceConfig.LoadCredentialEncrypted = lib.attrValues credentials;

      services.caddy = {
        globalConfig = ''
          oidc {
            issuer https://login.${fleet.dns.domain}
            client_id ${credential credentials.clientId}
            client_secret ${credential credentials.clientSecret}
            scope openid email profile groups
            username email
          }
        '';

        # Cookie only: these UIs are for browsers, so a bare bearer token never
        # gets in. Every allow rule needs a user match, or anonymous requests pass.
        extraConfig = ''
          (telemetry_ui_oidc) {
            oidc {
              authenticate cookie {
                name telemetry_ui_session
                secret ${credential credentials.cookieSecret}
                claim groups
                max_age 168h
              }
              allow {
                user *
                claim groups ${ui.adminGroup}
              }
            }
          }
        '';
      };

      # Access logs carry the Pocket ID email as user_id: Caddy logs
      # {http.auth.user.id}, which the oidc handler sets.
      services.gio.reverse-proxy.virtualHosts = {
        vmui = site cfg.services.vmselect "/select/0/vmui/";
        logs = site cfg.services.victorialogs "/select/vmui/";
        alertmanager = site cfg.services.alertmanager null;
      };
    };
}
