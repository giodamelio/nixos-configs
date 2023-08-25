_: {
  pkgs,
  config,
  ...
}: {
  age.secrets.service_authelia_jwt_secret = {
    file = ../../../secrets/service_authelia_jwt_secret.age;
    owner = config.services.authelia.instances.main.user;
    inherit (config.services.authelia.instances.main) group;
  };
  age.secrets.service_authelia_storage_encryption_key = {
    file = ../../../secrets/service_authelia_storage_encryption_key.age;
    owner = config.services.authelia.instances.main.user;
    inherit (config.services.authelia.instances.main) group;
  };
  age.secrets.service_authelia_ldap_password = {
    file = ../../../secrets/service_authelia_ldap_password.age;
    owner = config.services.authelia.instances.main.user;
    inherit (config.services.authelia.instances.main) group;
  };

  services.authelia.instances.main = {
    enable = true;

    settings = {
      theme = "auto";
      access_control = {
        default_policy = "deny";
        rules = [
          {
            domain = "auth-test.gio.ninja";
            policy = "one_factor";
          }
        ];
      };
      session = {
        domain = "authelia.gio.ninja";
      };
      storage = {
        postgres = {
          host = "/var/run/postgresql";
          port = 5432;
          database = "authelia";
          username = "fake";
          password = "fake";
        };
      };
      notifier = {
        filesystem = {
          filename = "/tmp/authelia-notifications.txt";
        };
      };
      authentication_backend = {
        # Password resets via Authelia work
        password_reset.disable = false;
        # Refresh users every minute
        refresh_interval = "1m";
        ldap = {
          implementation = "custom";
          url = "ldap://127.0.01:3890";
          base_dn = "dc=gio,dc=ninja";

          username_attribute = "uid";
          additional_users_dn = "ou=people";
          users_filter = "(&({username_attribute}={input})(objectClass=person))";

          additional_groups_dn = "ou=groups";
          groups_filter = "(member={dn})";
          group_name_attribute = "cn";

          mail_attribute = "mail";
          display_name_attribute = "displayName";

          # LDAP admin user
          user = "uid=admin,ou=people,dc=example,dc=com";
          # password = ""; # Set via environment variable pointing to file
        };
      };
    };

    secrets = {
      jwtSecretFile = config.age.secrets.service_authelia_jwt_secret.path;
      storageEncryptionKeyFile = config.age.secrets.service_authelia_storage_encryption_key.path;
    };

    environmentVariables = {
      AUTHELIA_AUTHENTICATION_BACKEND_LDAP_PASSWORD_FILE = config.age.secrets.service_authelia_ldap_password.path;
    };
  };

  services.postgresql = {
    enable = true;
    ensureDatabases = ["authelia"];
    ensureUsers = [
      {
        name = "authelia";
        ensurePermissions = {
          "DATABASE \"authelia\"" = "ALL PRIVILEGES";
        };
      }
    ];
  };
}
