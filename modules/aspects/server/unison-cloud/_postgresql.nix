{
  config,
  lib,
  pkgs,
  ...
}: let
  db = config.services.unison-cloud.database;
  passwords = {
    ${db.cloudApi.user} = "unison_cloud_api_db_password";
    ${db.nimbus.user} = "unison_cloud_nimbus_db_password";
  };

  # Core creates no roles; ensureUsers can't set passwords, and moddatetime needs a superuser.
  setupSql = pkgs.writeText "unison-cloud-postgresql-setup.sql" (
    lib.concatStrings (lib.mapAttrsToList (role: credential: ''
        \set password `cat "$CREDENTIALS_DIRECTORY/${credential}"`
        ALTER ROLE "${role}" PASSWORD :'password';
      '')
      passwords)
    + lib.concatMapStrings (database: ''
      REVOKE ALL ON DATABASE "${database}" FROM PUBLIC;
    '') [db.cloudApi.database db.nimbus.database]
    + ''
      \c "${db.cloudApi.database}"
      CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
      CREATE EXTENSION IF NOT EXISTS citext;
      CREATE EXTENSION IF NOT EXISTS moddatetime;
    ''
  );
in {
  assertions = [
    {
      assertion = db.cloudApi.user == db.cloudApi.database && db.nimbus.user == db.nimbus.database;
      message = "unison-cloud: ensureDBOwnership needs each database named after its role.";
    }
  ];

  services.postgresql = {
    ensureDatabases = [db.cloudApi.database db.nimbus.database];
    ensureUsers =
      map (name: {
        inherit name;
        ensureDBOwnership = true;
      })
      [db.cloudApi.user db.nimbus.user];
  };

  systemd.services.unison-cloud-postgresql-setup = {
    description = "Set the Unison Cloud PostgreSQL passwords and extensions";
    requires = ["postgresql-setup.service"];
    after = ["postgresql-setup.service"];
    requiredBy = ["unison-cloud-database.service"];
    before = ["unison-cloud-database.service"];
    path = [pkgs.coreutils];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      User = "postgres";
      Group = "postgres";
      LoadCredentialEncrypted = lib.attrValues passwords;
      ExecStart = "${config.services.postgresql.package}/bin/psql -X -q -v ON_ERROR_STOP=1 -d postgres -f ${setupSql}";
    };
  };
}
