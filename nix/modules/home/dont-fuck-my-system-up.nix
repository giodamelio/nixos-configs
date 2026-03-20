{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.gio.dont-fuck-my-system-up;

  mkWrapperScript = name: wrapper:
    pkgs.writeShellApplication {
      name = "dont-fuck-my-system-up-${name}";
      runtimeInputs = with pkgs; [bubblewrap coreutils];
      text = let
        roBindLines =
          lib.concatMapStringsSep "\n"
          (path: ''
            if [[ -e "${path}" ]]; then
              BWRAP_ARGS+=(--ro-bind "${path}" "${path}")
            fi'')
          wrapper.roBinds;

        rwBindLines =
          lib.concatMapStringsSep "\n"
          (path: ''
            if [[ -e "${path}" ]]; then
              BWRAP_ARGS+=(--bind "${path}" "${path}")
            fi'')
          wrapper.rwBinds;

        maskLines =
          lib.concatMapStringsSep "\n"
          (path: ''BWRAP_ARGS+=(--ro-bind /dev/null "${path}")'')
          wrapper.masks;

        projectDirSetup =
          if wrapper.projectDir != null
          then ''PROJECT_DIR="$(realpath "${wrapper.projectDir}")"''
          else ''PROJECT_DIR="$(realpath "$(pwd)")"'';

        homeSetup =
          if wrapper.ephemeral
          then ''BWRAP_ARGS+=(--tmpfs "$HOME")''
          else ''
            SANDBOX_HOMES="$HOME/.sandbox-homes"
            PROJECT_SLUG="''${PROJECT_DIR#/}"
            PROJECT_SLUG="''${PROJECT_SLUG//\//-}"
            OVERLAY_DIR="$SANDBOX_HOMES/$PROJECT_SLUG"
            OVERLAY_LOWER="$OVERLAY_DIR/lower"
            OVERLAY_UPPER="$OVERLAY_DIR/upper"
            OVERLAY_WORK="$OVERLAY_DIR/work"
            mkdir -p "$OVERLAY_LOWER" "$OVERLAY_UPPER" "$OVERLAY_WORK"
            BWRAP_ARGS+=(--overlay-src "$OVERLAY_LOWER" --overlay "$OVERLAY_UPPER" "$OVERLAY_WORK" "$HOME")'';

        networkLine = lib.optionalString (!wrapper.network) ''
          BWRAP_ARGS+=(--unshare-net)
        '';

        extraArgsStr = lib.concatStringsSep " " (map lib.escapeShellArg wrapper.extraArgs);
        extraArgsSuffix =
          if wrapper.extraArgs == []
          then ""
          else " ${extraArgsStr}";
      in ''
        set -euo pipefail

        ${projectDirSetup}

        ${homeSetup}

        BWRAP_ARGS=(
          # NixOS: bind /nix read-write (includes store, var, daemon socket)
          --bind /nix /nix

          # Bind /run for NixOS system (current-system symlinks, etc)
          --ro-bind /run /run

          # Essential /etc files
          --ro-bind /etc/resolv.conf /etc/resolv.conf
          --ro-bind /etc/ssl /etc/ssl
          --ro-bind /etc/static /etc/static
          --ro-bind /etc/localtime /etc/localtime
          --ro-bind /etc/passwd /etc/passwd
          --ro-bind /etc/group /etc/group
          --ro-bind /etc/hosts /etc/hosts
          --ro-bind /etc/profiles /etc/profiles

          # Proc and dev
          --proc /proc
          --dev /dev

          # Temp filesystem
          --tmpfs /tmp

          # Project directory read-write
          --bind "$PROJECT_DIR" "$PROJECT_DIR"

          # Working directory
          --chdir "$PROJECT_DIR"

          # Namespaces
          --unshare-pid
          --unshare-uts
          --die-with-parent
        )

        ${networkLine}

        # Read-only binds
        ${roBindLines}

        # Read-write binds
        ${rwBindLines}

        # Masked paths
        ${maskLines}

        exec bwrap "''${BWRAP_ARGS[@]}" -- ${lib.getExe wrapper.command}${extraArgsSuffix} "$@"
      '';
    };

  enabledWrappers = lib.filterAttrs (_: w: w.enable) cfg.wrappers;

  wrapperScripts = lib.mapAttrs mkWrapperScript enabledWrappers;

  aliasWrappers = lib.filterAttrs (_: w: w.alias.enable) enabledWrappers;
in {
  options.gio.dont-fuck-my-system-up = {
    enable = lib.mkEnableOption "bubblewrap sandbox wrappers";

    wrappers = lib.mkOption {
      type = lib.types.attrsOf (lib.types.submodule ({name, ...}: {
        options = {
          enable = lib.mkOption {
            type = lib.types.bool;
            default = true;
            description = "Whether to enable this wrapper.";
          };

          command = lib.mkOption {
            type = lib.types.package;
            description = "The package to wrap in a sandbox.";
          };

          extraArgs = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            default = [];
            description = "Extra arguments appended to the command.";
          };

          alias = {
            enable = lib.mkOption {
              type = lib.types.bool;
              default = true;
              description = "Whether to create shell aliases for this wrapper.";
            };

            name = lib.mkOption {
              type = lib.types.str;
              default = name;
              description = "Alias name for the sandboxed command. Defaults to the attr key.";
            };

            dangerousName = lib.mkOption {
              type = lib.types.str;
              default = "${name}-dangerous";
              description = "Alias name for the unsandboxed command.";
            };
          };

          roBinds = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            default = [];
            description = "Paths to bind read-only inside the sandbox.";
          };

          rwBinds = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            default = [];
            description = "Paths to bind read-write inside the sandbox.";
          };

          masks = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            default = [];
            description = "Paths to mask with /dev/null inside the sandbox.";
          };

          ephemeral = lib.mkOption {
            type = lib.types.bool;
            default = false;
            description = "Use tmpfs for home instead of a persistent overlay.";
          };

          network = lib.mkOption {
            type = lib.types.bool;
            default = true;
            description = "Enable network access inside the sandbox.";
          };

          projectDir = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = null;
            description = "Override the project directory. null uses PWD at runtime.";
          };
        };
      }));
      default = {};
      description = "Attrset of sandbox wrapper configurations.";
    };
  };

  config = lib.mkIf cfg.enable {
    home.packages = lib.attrValues wrapperScripts;

    home.shellAliases =
      lib.concatMapAttrs (name: wrapper: let
        script = wrapperScripts.${name};
        extraArgsStr = lib.concatStringsSep " " (map lib.escapeShellArg wrapper.extraArgs);
        dangerousSuffix =
          if wrapper.extraArgs == []
          then ""
          else " ${extraArgsStr}";
      in {
        ${wrapper.alias.name} = lib.getExe script;
        ${wrapper.alias.dangerousName} = "${lib.getExe wrapper.command}${dangerousSuffix}";
      })
      aliasWrappers;
  };
}
