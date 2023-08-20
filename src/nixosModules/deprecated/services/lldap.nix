# TODO: backup data
# currently that is the postgresql database `lldap` and `/var/lib/lldap/server_key`
{inputs, ...}: {
  pkgs,
  config,
  ...
}: {
  config = {
    environment = {
      systemPackages = with pkgs; [
        openldap

        # Easily list all the lldap users
        (pkgs.writeShellApplication {
          name = "lldap_list_users";
          runtimeInputs = with pkgs; [postgresql];
          text = ''
            sudo -u postgres psql -d lldap <<EOF
              SELECT u.user_id, u.display_name, ARRAY_AGG(g.display_name) AS group_names
              FROM public.users AS u
              LEFT JOIN public.memberships AS m ON u.user_id = m.user_id
              LEFT JOIN public.groups AS g ON m.group_id = g.group_id
              GROUP BY u.user_id, u.display_name;
            EOF
          '';
        })
      ];
    };

    # Define ragenix secrets
    age.secrets.service_lldap.file = ../../../secrets/service_lldap.age;

    # Run LLDAP
    services.lldap = {
      enable = true;
      environmentFile = config.age.secrets.service_lldap.path;
      settings = {
        # Admin User
        ldap_user_email = "admin@gio.ninja";
        ldap_user_dn = "admin";

        # Base DN that all users will be a part of
        ldap_base_dn = "dc=gio,dc=ninja";

        # Use postgresql for our data
        # Connects via the unix socket
        database_url = "postgresql:///lldap";
      };
    };

    # Setup database for lldap
    services.postgresql = {
      enable = true;
      ensureDatabases = ["lldap"];
      ensureUsers = [
        {
          name = "lldap";
          ensurePermissions = {
            "DATABASE \"lldap\"" = "ALL PRIVILEGES";
          };
        }
      ];
    };
  };
}
