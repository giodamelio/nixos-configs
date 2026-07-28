{lib, ...}: let
  inherit (lib) types mkOption mkEnableOption;
  inherit (import ./_lib.nix {inherit lib;}) screamingSnake;

  # generator.script accepts inline shell text, a path to an executable, or a
  # derivation (run via its mainProgram). Normalized in _lib at expansion time.
  scriptType = types.oneOf [types.str types.path types.package];

  generatorModule = types.submodule {
    options = {
      enable =
        mkEnableOption "generation for this secret"
        // {
          default = true;
          description = ''
            false = keep this generator config but behave as a manual secret
            (the provision unit fails with paste instructions). For pinning a
            value by hand without deleting the definition.
          '';
        };
      script = mkOption {
        type = types.nullOr scriptType;
        default = null;
        description = ''
          What produces the secret; its stdout becomes the value. Inline shell
          text (wrapped with `path` as PATH), a path to an executable, or a
          derivation (run via meta.mainProgram). Required when enable = true.
        '';
      };
      path = mkOption {
        type = types.functionTo (types.listOf types.package);
        default = _: [];
        defaultText = "pkgs: []";
        description = "Runtime PATH for inline `script` text, as pkgs: [ ... ].";
      };
      after = mkOption {
        type = types.listOf types.str;
        default = [];
        description = "Extra After= units for the provision unit (e.g. a service whose CLI mints the secret).";
      };
      needs = mkOption {
        type = types.listOf types.str;
        default = [];
        description = ''
          Other fleet.secrets this generator derives from. Each is loaded into
          the provision unit ($CREDENTIALS_DIRECTORY/<name>) and ordered after
          its target. Needed secrets must share this secret's origin.
        '';
      };
    };
  };

  # Whole-generator shorthand: any of the three script forms coerces to
  # { script = v; }. coercedTo checks scriptType (incl. derivations, which are
  # attrsets) BEFORE the submodule, so `generator = drv` / "openssl ..." work.
  generatorType = types.coercedTo scriptType (v: {script = v;}) generatorModule;

  # A single consumption site: use.<host>.services.<site>. `secretName` is
  # threaded in so credential.name / env-wrapper.variable can default to it.
  useSiteType = secretName:
    types.submodule ({name, ...}: {
      options = {
        enable = mkEnableOption "this use-site" // {default = true;};

        unit = mkOption {
          type = types.str;
          default = name;
          defaultText = "the site's attr name";
          description = "systemd unit to attach to, without \".service\".";
        };

        type = mkOption {
          type = types.enum ["credential" "env-wrapper"];
          default = "credential";
          description = "How the unit consumes the secret.";
        };

        credential = {
          name = mkOption {
            type = types.nullOr types.str;
            default = null;
            defaultText = "the secret name";
            description = "Credential id inside the unit; value appears at $CREDENTIALS_DIRECTORY/<name>.";
          };
          source = mkOption {
            type = types.nullOr types.str;
            default = null;
            description = ''
              Where systemd reads the credential from. null = search the
              credstores for the secret's blob by name; a relative string = a
              different blob name; an absolute path = a file or AF_UNIX socket.
            '';
          };
          encrypted = mkOption {
            type = types.bool;
            default = true;
            description = "true -> LoadCredentialEncrypted=; false -> LoadCredential= (requires source).";
          };
        };

        env-wrapper = {
          variable = mkOption {
            type = types.str;
            default = screamingSnake secretName;
            defaultText = "the secret name, SCREAMING_SNAKE_CASED";
            description = "Environment variable the ExecStart wrapper exports (type = env-wrapper).";
          };
        };

        restartOnChange = mkOption {
          type = types.bool;
          default = false;
          description = "try-restart this unit when a new value is delivered.";
        };

        upholds = mkOption {
          type = types.bool;
          default = false;
          description = "The secret's target Upholds= this unit (continuously restarts it while present) instead of plain Wants=.";
        };
      };
    });

  useHostType = secretName:
    types.submodule {
      options = {
        enable = mkEnableOption "this host's consumption" // {default = true;};
        services = mkOption {
          type = types.attrsOf (useSiteType secretName);
          default = {};
          description = "Consumption sites on this host: use.<host>.services.<site>.";
        };
      };
    };

  secretModule = {name, ...}: {
    options = {
      enable = mkEnableOption "this secret" // {default = true;};

      origin = mkOption {
        type = types.str;
        description = "Den host where the secret is created (required, even for manual secrets).";
      };

      generator = mkOption {
        type = types.nullOr generatorType;
        default = null;
        description = "How the secret is produced on the origin. null = manual (paste with `credsync write`).";
      };

      copyTo = mkOption {
        type = types.listOf types.str;
        default = [];
        description = "Extra hosts that receive the blob without a consumer (never list `use` hosts here).";
      };

      use = mkOption {
        type = types.attrsOf (useHostType name);
        default = {};
        description = "Consumption: use.<host>.services.<site>.";
      };
    };
  };
in {
  den.schema.fleet.imports = [
    {
      options.secrets = mkOption {
        type = types.attrsOf (types.submodule secretModule);
        default = {};
        description = ''
          Fleet-wide secret registry. Each entry describes a secret's whole
          lifecycle (origin, generator, copy set, use-sites) and expands into
          provision/push/holder systemd units across the involved hosts. See
          docs/archive/fleet-secrets-design-superseded.md.
        '';
      };

      # Off during the agevault migration: retires the credsync push oneshots
      # and their hourly retry timers fleet-wide. Provision/holder units stay.
      options.secretsPush.enable = mkOption {
        type = types.bool;
        default = false;
        description = "Emit the credsync push units/timers that deliver secrets to their copy set.";
      };
    }
  ];
}
