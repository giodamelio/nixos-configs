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

    # Mount some secrets for the service
    services.vault-agent.instances.lldap = {
      enable = true;
      settings = {
        vault = [
          {
            address = "http://127.0.0.1:8200";
          }
        ];
        auto_auth = [
          {
            method = [
              {
                type = "approle";
                config = {
                  role_id_file_path = "/var/run/credentials/vault-agent-lldap/role_id";
                  secret_id_file_path = "/var/run/credentials/vault-agent-lldap/secret_id";
                };
              }
            ];
          }
        ];
        template = [
          {
            destination = "/var/run/testing";
            contents = ''
              Hello World!
            '';
            error_on_missing_key = true;
          }
        ];
      };
    };
  };
}
