{...}: {
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.services.my-postgres;
in {
  options = {
    services.my-postgres = {
      enable = mkEnableOption (lib.mdDoc "PostgreSQL with Create DB and Users");
      databases = mkOption {
        type = types.attrsOf types.path;
        default = {};
      };
    };
  };

  # Ensure there is a database created for each item in cfg.databases
  # Also create a user with the same name that has all privileges over it
  config.services.postgresql = mkIf cfg.enable (let
    names = builtins.attrNames cfg.databases;
  in {
    enable = true;
    settings = {
      listen_addresses = lib.mkForce "*";
    };
    authentication = "host all all samenet md5";
    ensureDatabases = names;
    ensureUsers =
      builtins.map (name: {
        name = name;
        ensurePermissions = {
          "DATABASE ${name}" = "ALL PRIVILEGES";
        };
      })
      names;
  });

  # Add to the postStart script for the Postgres service to create passwords
  # for each user from the password files
  config.systemd.services.postgresql = mkIf cfg.enable (let
    names = builtins.attrNames cfg.databases;
    makeSetpasswordCommand = name:
      strings.concatStringsSep " " [
        ''$PSQL -tAc "ALTER ROLE''
        name
        ''WITH PASSWORD '$(cat $CREDENTIALS_DIRECTORY/${name}_postgres_password)'"''
      ];
    makeCredentialString = name: passwordFile: ''${name}_postgres_password:${passwordFile}'';
  in {
    # Add the psql commands to set the passwords
    postStart = ''
      # Set passwords for our users
      ${strings.concatMapStringsSep "\n" makeSetpasswordCommand names}
    '';

    # Load the files into the service as credentials
    serviceConfig.LoadCredential = attrsets.mapAttrsToList makeCredentialString cfg.databases;
  });
}
