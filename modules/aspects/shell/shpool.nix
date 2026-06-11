# shpool — persistent shell sessions, enabled on servers. Converted from
# nix/modules/home/shpool.nix. Reads the machine role from the host entity
# (den.schema host.role) via the parametric aspect form instead of the old
# per-user gio.role option.
_: {
  den.aspects.shpool = {host, ...}: {
    homeManager = {
      services.shpool = {
        enable = host.role == "server";
        settings = {
          session_restore_mode = {
            lines = 1000;
          };
        };
      };
    };
  };
}
