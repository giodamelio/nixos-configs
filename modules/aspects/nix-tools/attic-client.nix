# attic-client — push every build to the homelab Attic cache via a post-build
# hook. Converted from nix/modules/nixos/attic-client.nix.
_: {
  den.aspects.attic-client.nixos = {lib, ...}: {
    options.gio.attic-client = {
      cache = lib.mkOption {
        type = lib.types.str;
        default = "homelab";
        description = ''
          Name of the Attic cache to push to.
        '';
      };
    };
  };
}
