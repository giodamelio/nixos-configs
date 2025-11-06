{pkgs, ...}:
pkgs.writeShellApplication {
  name = "treebinderivation";
  runtimeInputs = with pkgs; [coreutils eza];
  text = ''
    # treebinderivation - Find executable, follow symlinks, and show derivation tree
    # Usage: treebinderivation <executable_name>

    set -euo pipefail

    main() {
        # Check if an argument was provided
        if [ $# -eq 0 ]; then
            echo "Usage: treebinderivation <executable_name>" >&2
            exit 1
        fi

        # Find the executable in PATH
        local exe_path
        exe_path=$(which "$1" 2>/dev/null) || {
            echo "Error: '$1' not found in PATH" >&2
            exit 1
        }

        # Follow symlink chain to find the final target
        local current_path="$exe_path"
        while [ -L "$current_path" ]; do
            local target
            target=$(readlink "$current_path")

            # If target is relative, resolve it relative to the symlink's directory
            if [[ "$target" != /* ]]; then
                local current_dir
                current_dir=$(dirname "$current_path")
                current_path="$current_dir/$target"
            else
                current_path="$target"
            fi
        done

        # Extract the Nix store derivation path
        # Pattern: /nix/store/hash-name/...
        if [[ "$current_path" =~ ^(/nix/store/[^/]+) ]]; then
            local derivation_path="''${BASH_REMATCH[1]}"
            echo "Derivation: $derivation_path"
            echo ""
            eza --tree "$derivation_path"
        else
            echo "Error: '$current_path' is not in a Nix store derivation" >&2
            exit 1
        fi
    }

    main "$@"
  '';
}
