{pkgs, ...}:
pkgs.writeShellApplication {
  name = "dont-fuck-my-system-up";
  runtimeInputs = with pkgs; [bubblewrap coreutils];
  text = ''
    set -euo pipefail

    usage() {
      echo "Usage: dont-fuck-my-system-up [OPTIONS] -- COMMAND [ARGS...]"
      echo ""
      echo "Run a command in a bubblewrap sandbox with limited filesystem access."
      echo ""
      echo "Options:"
      echo "  -d, --dir DIR      Project directory to bind read-write (default: PWD)"
      echo "  -r, --ro-bind PATH Bind a path read-only (can be repeated)"
      echo "  -w, --rw-bind PATH Bind a path read-write (can be repeated)"
      echo "  -m, --mask PATH    Mask a file with /dev/null (can be repeated)"
      echo "  -e, --ephemeral    Use tmpfs for home (no persistence, default: overlay)"
      echo "  -n, --no-network   Disable network access"
      echo "  -h, --help         Show this help"
      exit 0
    }

    PROJECT_DIR="$(pwd)"
    EXTRA_RO_BINDS=()
    EXTRA_RW_BINDS=()
    MASK_FILES=()
    NO_NETWORK=false
    EPHEMERAL=false

    while [[ $# -gt 0 ]]; do
      case "$1" in
        -d|--dir)
          PROJECT_DIR="$2"
          shift 2
          ;;
        -r|--ro-bind)
          EXTRA_RO_BINDS+=("$2")
          shift 2
          ;;
        -w|--rw-bind)
          EXTRA_RW_BINDS+=("$2")
          shift 2
          ;;
        -m|--mask)
          MASK_FILES+=("$2")
          shift 2
          ;;
        -e|--ephemeral)
          EPHEMERAL=true
          shift
          ;;
        -n|--no-network)
          NO_NETWORK=true
          shift
          ;;
        -h|--help)
          usage
          ;;
        --)
          shift
          break
          ;;
        *)
          break
          ;;
      esac
    done

    if [[ $# -eq 0 ]]; then
      echo "Error: No command specified" >&2
      usage
    fi

    # Resolve command to full nix store path before entering sandbox
    CMD="$1"
    shift
    CMD_PATH="$(command -v "$CMD" 2>/dev/null)" || {
      echo "Error: Command not found: $CMD" >&2
      exit 1
    }
    # Resolve symlinks to get actual nix store path
    CMD_PATH="$(realpath "$CMD_PATH")"

    PROJECT_DIR="$(realpath "$PROJECT_DIR")"

    # Setup persistent overlay for home directory
    SANDBOX_HOMES="$HOME/.sandbox-homes"
    PROJECT_SLUG="''${PROJECT_DIR#/}"
    PROJECT_SLUG="''${PROJECT_SLUG//\//-}"
    OVERLAY_DIR="$SANDBOX_HOMES/$PROJECT_SLUG"
    OVERLAY_LOWER="$OVERLAY_DIR/lower"
    OVERLAY_UPPER="$OVERLAY_DIR/upper"
    OVERLAY_WORK="$OVERLAY_DIR/work"

    if [[ "$EPHEMERAL" != "true" ]]; then
      mkdir -p "$OVERLAY_LOWER" "$OVERLAY_UPPER" "$OVERLAY_WORK"
    fi

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
    )

    # User home directory: overlay (persistent) or tmpfs (ephemeral)
    if [[ "$EPHEMERAL" == "true" ]]; then
      BWRAP_ARGS+=(--tmpfs "$HOME")
    else
      BWRAP_ARGS+=(--overlay-src "$OVERLAY_LOWER" --overlay "$OVERLAY_UPPER" "$OVERLAY_WORK" "$HOME")
    fi

    BWRAP_ARGS+=(
      # Project directory read-write
      --bind "$PROJECT_DIR" "$PROJECT_DIR"

      # Working directory
      --chdir "$PROJECT_DIR"

      # Namespaces
      --unshare-pid
      --unshare-uts
      --die-with-parent
    )

    # Add network namespace if requested
    if [[ "$NO_NETWORK" == "true" ]]; then
      BWRAP_ARGS+=(--unshare-net)
    fi

    # Bind common dotfiles/directories if they exist (read-write for app state)
    for dotpath in \
      "$HOME/.claude" \
      "$HOME/.claude.json" \
      "$HOME/.config/claude" \
      "$HOME/.cache/claude" \
      "$HOME/.cache/claude-cli-nodejs" \
      "$HOME/.local/state/claude" \
      "$HOME/.omp" \
      "$HOME/.config/omp"
    do
      if [[ -e "$dotpath" ]]; then
        BWRAP_ARGS+=(--bind "$dotpath" "$dotpath")
      fi
    done

    # Bind configs read-only
    for dotpath in \
      "$HOME/.gitconfig" \
      "$HOME/.config/git" \
      "$HOME/.config/nix" \
      /etc/nix
    do
      if [[ -e "$dotpath" ]]; then
        BWRAP_ARGS+=(--ro-bind "$dotpath" "$dotpath")
      fi
    done

    # Add extra read-only binds
    for path in "''${EXTRA_RO_BINDS[@]}"; do
      if [[ -e "$path" ]]; then
        BWRAP_ARGS+=(--ro-bind "$path" "$path")
      else
        echo "Warning: ro-bind path does not exist: $path" >&2
      fi
    done

    # Add extra read-write binds
    for path in "''${EXTRA_RW_BINDS[@]}"; do
      if [[ -e "$path" ]]; then
        BWRAP_ARGS+=(--bind "$path" "$path")
      else
        echo "Warning: rw-bind path does not exist: $path" >&2
      fi
    done

    # Mask files with /dev/null
    for path in "''${MASK_FILES[@]}"; do
      BWRAP_ARGS+=(--ro-bind /dev/null "$path")
    done

    exec bwrap "''${BWRAP_ARGS[@]}" -- "$CMD_PATH" "$@"
  '';
}
