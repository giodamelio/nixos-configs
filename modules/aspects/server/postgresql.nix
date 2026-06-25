# postgresql — shared PostgreSQL server. Host-attached; services that need a
# database layer on their own ensureDatabases/ensureUsers + peer-auth identMap
# via lib.mkAfter. Converted from nix/hosts/{gallium,carbon}/postgresql.nix.
_: {
  den.aspects.postgresql.nixos = {pkgs, ...}: {
    environment.systemPackages = [pkgs.pgcli];

    services.postgresql.enable = true;
  };
}
