{
  lib,
  config,
  pkgs,
  ...
}: let
  cfg = config.gio.attic-client;

  post-build-hook = pkgs.writeShellScript "attic-post-build-hook" ''
    set -euo pipefail
    export PATH="${lib.makeBinPath [pkgs.attic-client]}:$PATH"
    if [[ -n "''${OUT_PATHS:-}" ]]; then
      attic push ${lib.escapeShellArg cfg.cache} $OUT_PATHS
    fi
  '';
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
