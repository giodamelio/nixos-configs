# fleet.credentials: the read-only manifest + eval-time verification layer for
# the age-based secret system (agevault, modules/packages/agevault). Reads the
# names-only TOML manifest that `agevault generate-toml` commits (repo root by
# default, path configurable), exposes it as read-only facts other aspects can
# consume, and asserts that every credential a host declares it `needs` is
# actually deliverable.
#
# Built alongside the credsync `fleet.secrets` aspect during the migration: a
# secret is cut over by moving it from a fleet.secrets use-site to a
# fleet.credentials.needs entry here. The eventual goal is to fold delivery
# (the fleet.secrets successor) and consumption into this one namespace.
_: {
  den.aspects.fleet-credentials.nixos = {
    host,
    config,
    lib,
    ...
  }: let
    cfg = config.fleet.credentials;

    # Names-only TOML manifest written by `agevault generate-toml` (its
    # manifest_path points at cfg.manifestFile). A missing file is a hard error,
    # never a silent empty manifest.
    manifest =
      if builtins.pathExists cfg.manifestFile
      then builtins.fromTOML (builtins.readFile cfg.manifestFile)
      else throw "fleet.credentials: manifest '${toString cfg.manifestFile}' is missing. Run `agevault generate-toml` in the secrets repo (its manifest_path must point at this file) and commit the result.";

    available = manifest.${host.name} or [];
    missing = builtins.filter (n: !(builtins.elem n available)) cfg.needs;
  in {
    options.fleet.credentials = {
      manifestFile = lib.mkOption {
        type = lib.types.path;
        default = ../../../secrets.toml;
        defaultText = lib.literalExpression "\${self}/secrets.toml";
        description = ''
          The committed agevault TOML manifest (host -> credential names).
          agevault's `manifest_path` must point at this same file.
        '';
      };

      needs = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [];
        example = ["secrets.json" "netdata-api-key"];
        description = ''
          Credential names this host consumes from agevault. Declaring one
          asserts at eval time that agevault can deliver it -- i.e. that it is
          in the manifest for this host. Migrate a secret off fleet.secrets by
          moving it here; a typo or an un-generated blob then becomes a build
          error instead of a boot-time failure.
        '';
      };

      manifest = lib.mkOption {
        type = lib.types.attrsOf (lib.types.listOf lib.types.str);
        readOnly = true;
        default = manifest;
        description = "The whole names-only agevault manifest (host -> credential names).";
      };

      available = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        readOnly = true;
        default = available;
        description = "Credential names agevault can deliver to THIS host (from the manifest).";
      };
    };

    config.assertions = [
      {
        assertion = missing == [];
        message = "fleet.credentials: ${host.name} needs credential(s) not in the agevault manifest (${toString cfg.manifestFile}): ${lib.concatStringsSep ", " missing}. Add each with `agevault edit ${host.name} <name>` (auto-runs generate-toml) and commit the manifest, or drop it from fleet.credentials.needs.";
      }
    ];
  };
}
