{
  pkgs,
  inputs,
}:
inputs.jail-nix.lib.extend {
  inherit pkgs;
  basePermissions = c:
    with c; [
      # Same as default base but without --clearenv
      (unsafe-add-raw-args "--proc /proc")
      (unsafe-add-raw-args "--dev /dev")
      (unsafe-add-raw-args "--tmpfs /tmp")
      (unsafe-add-raw-args "--tmpfs ~")
      (ro-bind "${pkgs.bash}/bin/sh" "/bin/sh")
      (add-pkg-deps [pkgs.coreutils])
      (fwd-env "PATH")
      bind-nix-store-runtime-closure
      fake-passwd
    ];
  additionalCombinators = combinators:
    with combinators; {
      # Read paths from a file and bind them read-write at runtime
      rw-paths-from-file = filename:
        add-runtime ''
          SANDBOX_PATHS_FILE="$PWD/${filename}"
          if [[ -f "$SANDBOX_PATHS_FILE" ]]; then
            while IFS= read -r line || [[ -n "$line" ]]; do
              [[ -z "$line" || "$line" == \#* ]] && continue
              line="''${line/#\~/$HOME}"
              if [[ -e "$line" ]]; then
                RUNTIME_ARGS+=(--bind "$line" "$line")
              fi
            done < "$SANDBOX_PATHS_FILE"
            RUNTIME_ARGS+=(--ro-bind "$SANDBOX_PATHS_FILE" "$SANDBOX_PATHS_FILE")
          fi
        '';

      # Per-project overlay home keyed on $PWD
      overlay-home = add-runtime ''
        PROJECT_DIR="$(realpath "$PWD")"
        PROJECT_SLUG="''${PROJECT_DIR#/}"
        PROJECT_SLUG="''${PROJECT_SLUG//\//-}"
        OVERLAY_DIR="$HOME/.local/share/jail.nix/overlay-homes/$PROJECT_SLUG"
        OVERLAY_LOWER="$OVERLAY_DIR/lower"
        OVERLAY_UPPER="$OVERLAY_DIR/upper"
        OVERLAY_WORK="$OVERLAY_DIR/work"
        mkdir -p "$OVERLAY_LOWER" "$OVERLAY_UPPER" "$OVERLAY_WORK"
        RUNTIME_ARGS+=(--overlay-src "$OVERLAY_LOWER" --overlay "$OVERLAY_UPPER" "$OVERLAY_WORK" "$HOME")
      '';

      # Bind the working directory read-write and chdir into it
      work-in-cwd = include-once "work-in-cwd" (add-runtime ''
        RUNTIME_ARGS+=(--bind "$PWD" "$PWD" --chdir "$PWD")
      '');

      # Override try-readwrite to use RUNTIME_ARGS so binds layer after overlay-home
      try-readwrite = path:
        add-runtime ''
          RUNTIME_ARGS+=(--bind-try ${escape path} ${escape path})
        '';

      # Override try-readonly to use RUNTIME_ARGS so binds layer after overlay-home
      try-readonly = path:
        add-runtime ''
          RUNTIME_ARGS+=(--ro-bind-try ${escape path} ${escape path})
        '';

      # Mask a path with /dev/null
      mask = path: ro-bind "/dev/null" path;

      # Unset an environment variable inside the jail
      unset-env = var:
        add-runtime ''
          RUNTIME_ARGS+=(--unsetenv ${escape var})
        '';

      # Prepend extra arguments before "$@"
      extra-args = args: state:
        state
        // {
          argv = (pkgs.lib.concatStringsSep " " (builtins.map escape args)) + " " + state.argv;
        };
    };
}
