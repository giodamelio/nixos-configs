_: {
  den.aspects.gallium.nixos = {lib, ...}: {
    services.vikunja = {
      enable = true;
      frontendScheme = "https";
      frontendHostname = "vikunja.gio.ninja";
      address = "127.0.0.1";
      port = 3456;

      database = {
        type = "postgres";
        user = "vikunja";
        database = "vikunja";
        host = "/run/postgresql";
      };

      settings = {
        service = {
          # `<key>.file` is vikunja's own credential hook (readConfigValuesFromFiles).
          # Unset, service.secret is regenerated per restart and every session dies.
          secret.file = "/run/credentials/vikunja.service/vikunja_service_secret";
          enableregistration = false;
          timezone = "America/Los_Angeles";
        };

        mailer = {
          enabled = true;
          host = "smtp.fastmail.com";
          port = 587;
          authtype = "plain";
          username = "giodamelio@fastmail.com";
          password.file = "/run/credentials/vikunja.service/vikunja_fastmail_smtp_password";
          fromemail = "vikunja@gio.ninja";
        };
      };
    };

    # agevault delivers these (asserted against secrets.toml at eval time);
    # vikunja reads them itself via the `<key>.file` settings above.
    fleet.credentials.needs = [
      "vikunja_service_secret"
      "vikunja_fastmail_smtp_password"
    ];

    systemd.services.vikunja.serviceConfig.LoadCredentialEncrypted = [
      "vikunja_service_secret"
      "vikunja_fastmail_smtp_password"
    ];

    services.postgresql = {
      ensureDatabases = ["vikunja"];
      ensureUsers = [
        {
          name = "vikunja";
          ensureDBOwnership = true;
        }
      ];
      # DynamicUser names the runtime user `vikunja`; the root entry is what lets
      # `vikunja user create` work from a root shell.
      identMap = lib.mkAfter ''
        vikunja root vikunja
        vikunja vikunja vikunja
      '';
      authentication = lib.mkAfter ''
        local all vikunja peer map=vikunja
      '';
    };
  };

  den.hosts.x86_64-linux.gallium.services.vikunja = {
    endpoint = {
      domain = "vikunja";
      backend.host = "localhost";
      backend.port = 3456;
    };
    healthcheck.target = "https://vikunja.gio.ninja/health";
  };
}
