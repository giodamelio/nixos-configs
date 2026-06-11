# zmx — terminal multiplexer, installed on servers. Converted from
# nix/modules/home/zmx.nix. Reads the machine role from the host entity
# (den.schema host.role) via the parametric aspect form; `perSystem` is a module
# arg from the per-system aspect.
_: {
  den.aspects.zmx = {host, ...}: {
    homeManager = {perSystem, ...}: {
      home.packages =
        if host.role == "server"
        then [perSystem.zmx.default]
        else [];
    };
  };
}
