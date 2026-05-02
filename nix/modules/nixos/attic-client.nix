{
  lib,
  config,
  pkgs,
  ...
}: let
  cfg = config.gio.attic-client;

  post-build-hook = lib.getExe (pkgs.writeShellApplication {
    name = "attic-post-build-hook";
    runtimeInputs = [pkgs.attic-client];
    text = ''
      if [[ -n "''${OUT_PATHS:-}" ]]; then
        # Word splitting is intentional: OUT_PATHS is a space-separated list from Nix
      # shellcheck disable=SC2086
      attic push ${lib.escapeShellArg cfg.cache} $OUT_PATHS
      fi
    '';
  });
in {
  options.gio.attic-client = {
    cache = lib.mkOption {
      type = lib.types.str;
      default = "homelab";
      description = ''
        Name of the Attic cache to push to.
      '';
    };
  };

  config = {
    nix.settings.post-build-hook = post-build-hook;
  };
}
