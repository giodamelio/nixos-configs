# role — a first-class machine attribute on the den host entity, replacing the
# old per-user `gio.role` Home-Manager option. "role" is a property of the
# machine, not the user, so it belongs on the host: set it once per host with
# `den.hosts.<sys>.<host>.role = "desktop"`, and aspects read it from the `host`
# context (e.g. `den.aspects.shpool = {host, ...}: ...; host.role == "server"`).
#
# https://den.denful.dev/explanation/entities/#schema-shared-options-across-a-kind
{lib, ...}: {
  den.schema.host.imports = [
    {
      options.role = lib.mkOption {
        type = lib.types.enum ["server" "desktop"];
        default = "server";
        description = "The role of the machine (drives role-specific aspects like shpool/zmx).";
      };
    }
  ];
}
