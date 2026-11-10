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
          SANDBOX_PATHS_FILE="$(realpath -m -- "$PWD/${filename}")"
          if [[ -f "$SANDBOX_PATHS_FILE" ]]; then
            while IFS= read -r line || [[ -n "$line" ]]; do
              [[ -z "$line" || "$line" == \#* ]] && continue
              line="''${line/#\~/$HOME}"
              # bwrap needs absolute paths, so resolve relative entries (e.g. ../Data) against $PWD
              line="$(realpath -m -- "$line")"
              if [[ -e "$line" ]]; then
                RUNTIME_ARGS+=(--bind "$line" "$line")
              fi
            done < "$SANDBOX_PATHS_FILE"
            # ro-bind the file itself last so the agent can't edit it to widen its own sandbox
            RUNTIME_ARGS+=(--ro-bind "$SANDBOX_PATHS_FILE" "$SANDBOX_PATHS_FILE")
          fi
        '';

      # Dev-bind USB character devices listed in a file. Entries must be udev
      # symlinks directly under /dev/jail, so the host's udev rules are the
      # allowlist. Only the device's own USB sysfs subtree is exposed.
      devices-from-file = filename:
        add-runtime ''
          SANDBOX_DEVICES_FILE="$(realpath -m -- "$PWD/${filename}")"
          if [[ -f "$SANDBOX_DEVICES_FILE" ]]; then
            declare -A SANDBOX_SYSFS_SEEN=()
            while IFS= read -r line || [[ -n "$line" ]]; do
              [[ -z "$line" || "$line" == \#* ]] && continue
              if [[ ! "$line" =~ ^/dev/jail/[^/]+$ || "$line" == /dev/jail/. || "$line" == /dev/jail/.. ]]; then
                echo "jail: device entry $line is not a /dev/jail/<name> udev symlink" >&2
                exit 1
              fi
              dev="$(realpath -m -- "$line")"
              if [[ ! -e "$dev" ]]; then
                echo "jail: device $line not present, skipping" >&2
                continue
              fi
              if [[ ! -c "$dev" || "$dev" != /dev/* ]]; then
                echo "jail: $line resolves to $dev, which is not a character device under /dev" >&2
                exit 1
              fi
              sysdev="$(realpath -e -- "/sys/dev/char/$((16#$(stat -c %t -- "$dev"))):$((16#$(stat -c %T -- "$dev")))")"
              usbdev="$sysdev"
              while [[ "$usbdev" == /sys/devices/* && ! -f "$usbdev/idVendor" ]]; do
                usbdev="$(dirname -- "$usbdev")"
              done
              if [[ "$usbdev" != /sys/devices/* ]]; then
                echo "jail: $line ($sysdev) has no USB device ancestor in sysfs" >&2
                exit 1
              fi
              RUNTIME_ARGS+=(--dev-bind "$dev" "$dev")
              if [[ -z "''${SANDBOX_SYSFS_SEEN[$usbdev]:-}" ]]; then
                RUNTIME_ARGS+=(--ro-bind "$usbdev" "$usbdev")
                SANDBOX_SYSFS_SEEN[$usbdev]=1
              fi
              # HID enumeration walks /sys/class/<subsystem>; only bound devices get an entry there.
              if [[ -z "''${SANDBOX_SYSFS_SEEN[$sysdev]:-}" ]]; then
                subsystem="$(basename -- "$(readlink -- "$sysdev/subsystem")")"
                RUNTIME_ARGS+=(--symlink "$sysdev" "/sys/class/$subsystem/$(basename -- "$sysdev")")
                SANDBOX_SYSFS_SEEN[$sysdev]=1
              fi
            done < "$SANDBOX_DEVICES_FILE"
            RUNTIME_ARGS+=(--ro-bind "$SANDBOX_DEVICES_FILE" "$SANDBOX_DEVICES_FILE")
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

      # When CWD is a secondary jj workspace, its .jj/repo is a file pointing
      # at the backing repo's .jj/repo. Bind only that shared store and the git
      # dir behind it, not the backing workspace, so the agent cannot touch the
      # parent's or siblings' working files.
      bind-jj-workspace-store = add-runtime ''
        if [[ -f "$PWD/.jj/repo" ]]; then
          JJ_STORE="$(realpath -m "$PWD/.jj/$(cat "$PWD/.jj/repo")")"
          if [[ -d "$JJ_STORE/store" ]]; then
            RUNTIME_ARGS+=(--bind "$JJ_STORE" "$JJ_STORE")
            if [[ -f "$JJ_STORE/store/git_target" ]]; then
              JJ_GIT_DIR="$(realpath -m "$JJ_STORE/store/$(head -n 1 "$JJ_STORE/store/git_target")")"
              if [[ -d "$JJ_GIT_DIR" ]]; then
                RUNTIME_ARGS+=(--bind "$JJ_GIT_DIR" "$JJ_GIT_DIR")
              fi
            fi
          fi
        fi
      '';

      # Same as upstream network, minus /run/systemd/resolve: it holds
      # resolved's varlink sockets. Only the file /etc/resolv.conf links to
      # (the stub under /run/systemd/resolve) is bound, so the symlink resolves.
      network = include-once "network" (state:
        compose [
          time-zone
          (share-ns "net")
          (runtime-deep-ro-bind "/etc/hosts")
          (runtime-deep-ro-bind "/etc/nsswitch.conf")
          (runtime-deep-ro-bind "/etc/resolv.conf")
          (add-runtime ''
            if [[ -L /etc/resolv.conf ]]; then
              RESOLV_TARGET="$(realpath /etc/resolv.conf)"
              RUNTIME_ARGS+=(--ro-bind "$RESOLV_TARGET" "$RESOLV_TARGET")
            fi
          '')
          (runtime-deep-ro-bind "/etc/ssl")
          (write-text "/etc/hostname" "${state.hostname}\n")
          (unsafe-add-raw-args "--hostname ${escape state.hostname}")
        ]
        state);

      # The trusted daemon socket is root-equivalent. This is a proxy that
      # forces the connection untrusted; served by the nix-daemon-untrusted
      # user socket in the claude-code aspect.
      # NIX_REMOTE is forced because nix's auto store picks the local store
      # when the bwrap-created /nix/var/nix is owned by the user.
      untrusted-nix-daemon = add-runtime ''
        RUNTIME_ARGS+=(--bind-try "$XDG_RUNTIME_DIR/nix-daemon-untrusted.sock" /nix/var/nix/daemon-socket/socket)
        RUNTIME_ARGS+=(--setenv NIX_REMOTE daemon)
      '';

      # Keeps tool caches (including nix's fetcher cache, which the host would
      # trust) out of the host's ~/.cache.
      private-cache = add-runtime ''
        JAIL_CACHE="$HOME/.local/share/jail.nix/cache"
        mkdir -p "$JAIL_CACHE"
        RUNTIME_ARGS+=(--bind "$JAIL_CACHE" "$HOME/.cache")
      '';

      # Must come after every bind under ~, since bwrap cannot create mount
      # points on a read-only tmpfs.
      readonly-home = add-runtime ''
        RUNTIME_ARGS+=(--remount-ro "$HOME")
      '';

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

      # Hands the jail only this project's bot token, since the jail has no
      # session bus to reach the keyring itself.
      veans-token = add-runtime ''
        if [[ -f "$PWD/.veans.yml" ]]; then
          VEANS_ACCOUNT="$(${pkgs.yq-go}/bin/yq '.server + "::" + .bot.username' "$PWD/.veans.yml")"
          if ! VEANS_TOKEN="$(${pkgs.libsecret}/bin/secret-tool lookup service veans username "$VEANS_ACCOUNT")"; then
            echo "jail: no veans token in keyring for $VEANS_ACCOUNT" >&2
            exit 1
          fi
          RUNTIME_ARGS+=(--setenv VEANS_TOKEN "$VEANS_TOKEN")
        fi
      '';

      # The agent-dms app password for this project; the CLI works out the
      # address and workspace itself from the repo.
      agent-dms-token = add-runtime ''
        if [[ -f "$PWD/.agent-dms.yml" ]]; then
          AGENT_DMS_PROJECT="$(${pkgs.yq-go}/bin/yq '.name' "$PWD/.agent-dms.yml")"
          if ! AGENT_DMS_PASSWORD="$(${pkgs.libsecret}/bin/secret-tool lookup service agent-dms project "$AGENT_DMS_PROJECT")"; then
            echo "jail: no agent-dms password in keyring for $AGENT_DMS_PROJECT, run agent-dms init outside the jail" >&2
            exit 1
          fi
          RUNTIME_ARGS+=(--setenv AGENT_DMS_PASSWORD "$AGENT_DMS_PASSWORD")
        fi
      '';

      # Public-repo read-only PAT, only to lift the unauthenticated rate limit.
      github-token = add-runtime ''
        if ! GITHUB_TOKEN="$(${pkgs.libsecret}/bin/secret-tool lookup service github-readonly)"; then
          echo "jail: no github-readonly token in keyring" >&2
          exit 1
        fi
        RUNTIME_ARGS+=(--setenv GITHUB_TOKEN "$GITHUB_TOKEN" --setenv GH_TOKEN "$GITHUB_TOKEN")
      '';

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
