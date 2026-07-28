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
    pkgs,
    ...
  }: let
    cfg = config.fleet.credentials;

    # --- unit_wrappers: credential -> process environment -----------------
    # Units asking for at least one variable.
    wrapped = lib.filterAttrs (_unit: w: w.environment != {}) cfg.unit_wrappers;

    credsOf = w: lib.unique (lib.attrValues w.environment);

    # A drop-in that blanks ExecStart and re-points it at a script exporting each
    # variable from the credentials directory, then execs the original command.
    # Emitted as its own package (via systemd.packages) rather than by setting
    # serviceConfig.ExecStart, which would be self-referential.
    envDropin = unit: w: let
      rawExecStart = config.systemd.services.${unit}.serviceConfig.ExecStart or null;

      # Plain units give a string/path/derivation; modular services render a
      # list (nixos/modules/system/service/systemd/service.nix builds
      # `ExecStart = [ mainExecStart ... ]`). Either is wrappable as long as it
      # resolves to exactly one command.
      origExecStart =
        if builtins.isList rawExecStart
        then
          if builtins.length rawExecStart == 1
          then builtins.head rawExecStart
          else null
        else rawExecStart;

      exports =
        lib.sort (a: b: a.var < b.var)
        (lib.mapAttrsToList (var: cred: {inherit var cred;}) w.environment);

      checked =
        if origExecStart == null
        then throw "fleet.credentials: unit_wrappers.${unit} needs exactly one ExecStart on ${unit}.service (found none, or several)"
        else true;

      # writeShellScript, not writeShellApplication: this execs the original
      # ExecStart verbatim, which `set -u` and shellcheck would both fight.
      script = pkgs.writeShellScript "${unit}-credential-env" ''
        ${lib.concatMapStringsSep "\n" (e: ''export ${e.var}="$(cat "$CREDENTIALS_DIRECTORY/${e.cred}")"'') exports}
        exec ${origExecStart}
      '';
    in
      assert checked;
        pkgs.runCommandLocal "credential-env-${unit}" {} ''
          d="$out/etc/systemd/system/${unit}.service.d"
          mkdir -p "$d"
          cat > "$d/60-credential-env.conf" <<EOF
          [Service]
          ExecStart=
          ExecStart=${script}
          EOF
        '';

    # Names-only TOML manifest written by `agevault generate-toml` (its
    # manifest_path points at cfg.manifestFile). A missing file is a hard error,
    # never a silent empty manifest.
    manifest =
      if builtins.pathExists cfg.manifestFile
      then builtins.fromTOML (builtins.readFile cfg.manifestFile)
      else throw "fleet.credentials: manifest '${toString cfg.manifestFile}' is missing. Run `agevault generate-toml` in the secrets repo (its manifest_path must point at this file) and commit the result.";

    available = manifest.${host.name} or [];
    missing = builtins.filter (n: !(builtins.elem n available)) cfg.needs;
    # agevault credential names are snake_case; a dash means a stale hyphenated
    # name that agevault won't deliver under that spelling.
    dashed = builtins.filter (lib.hasInfix "-") cfg.needs;
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
        example = ["secrets.json" "netdata_api_key"];
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

      unit_wrappers = lib.mkOption {
        default = {};
        example = lib.literalExpression ''
          {
            someservice.environment.SERVICE_API_KEY = "service_api_key";
          }
        '';
        description = ''
          Per-unit credential consumption for services that cannot read a
          credential file themselves. Keyed by systemd unit name without
          ".service"; works for modular services too, since those render into
          systemd.services.

          Declaring one is enough: the credential is added to `needs` (so the
          manifest assertion covers it), loaded onto the unit with
          LoadCredentialEncrypted, and exported into the process environment.
        '';
        type = lib.types.attrsOf (lib.types.submodule {
          options.environment = lib.mkOption {
            type = lib.types.attrsOf lib.types.str;
            default = {};
            example = {API_KEY = "service_api_key";};
            description = ''
              Environment variable -> credential name. Each pair becomes an
              `export VAR="$(cat $CREDENTIALS_DIRECTORY/<name>)"` ahead of the
              unit's original ExecStart.

              This exists because EnvironmentFile= cannot reference
              /run/credentials: systemd loads environment files when it spawns
              each Exec* line, before that invocation's credentials exist.
            '';
          };
        });
      };
    };

    config = lib.mkMerge [
      {
        # Declaring a wrapper is the whole declaration: the name is asserted
        # against the manifest and the blob is loaded onto the unit.
        fleet.credentials.needs = lib.unique (lib.concatMap credsOf (lib.attrValues wrapped));

        systemd.packages = lib.mapAttrsToList envDropin wrapped;

        systemd.services =
          lib.mapAttrs (_unit: w: {
            serviceConfig.LoadCredentialEncrypted = credsOf w;
          })
          wrapped;
      }

      {
        assertions = [
          {
            assertion = missing == [];
            message = "fleet.credentials: ${host.name} needs credential(s) not in the agevault manifest (${toString cfg.manifestFile}): ${lib.concatStringsSep ", " missing}. Add each with `agevault edit ${host.name} <name>` (auto-runs generate-toml) and commit the manifest, or drop it from fleet.credentials.needs.";
          }
          {
            assertion = dashed == [];
            message = "fleet.credentials: ${host.name} needs credential(s) with a dash in the name: ${lib.concatStringsSep ", " dashed}. agevault credential names are snake_case — rename the secret and its use-sites to use underscores.";
          }
        ];
      }
    ];
  };
}
