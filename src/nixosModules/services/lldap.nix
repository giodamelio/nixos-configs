{inputs, ...}: {
  pkgs,
  config,
  ...
}: {
  config = {
    environment = {
      systemPackages = with pkgs; [
        openldap
      ];
    };

    # Define ragenix secrets
    age.secrets.lldap_jwt_secret.file = ../../../secrets/lldap_jwt_secret.age;
    age.secrets.lldap_default_admin_password.file = ../../../secrets/lldap_default_admin_password.age;

    # Run LLDAP
    services.lldap = {
      enable = true;
      settings = {
        # Admin User
        ldap_user_email = "admin@gio.ninja";
        ldap_user_dn = "admin";

        # Base DN that all users will be a part of
        ldap_base_dn = "dc=gio,dc=ninja";
      };
    };

    # Small overide of systemd service to load the credentials via systemd LoadCredential
    systemd.services.lldap = {
      serviceConfig = {
        LoadCredential = [
          ("jwt_secret:" + config.age.secrets.lldap_jwt_secret.path)
          ("default_admin_password:" + config.age.secrets.lldap_default_admin_password.path)
        ];
      };
      environment = {
        LLDAP_JWT_SECRET_FILE = "%d/jwt_secret";
        LLDAP_LDAP_USER_PASS_FILE = "%d/default_admin_password";
      };
    };
  };
}
