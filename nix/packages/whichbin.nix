{pkgs, ...}:
pkgs.writeShellApplication {
  name = "whichbin";
  runtimeInputs = with pkgs; [coreutils];
  text = ''
    # whichbin - Find executables in PATH and follow symlink chains
    # Usage: whichbin <executable_name>

    set -euo pipefail

    main() {
        # Check if an argument was provided
        if [ $# -eq 0 ]; then
            echo "Usage: whichbin <executable_name>" >&2
            exit 1
        fi

        # Find the executable in PATH
        local exe_path
        exe_path=$(which "$1" 2>/dev/null) || {
            echo "Error: '$1' not found in PATH" >&2
            exit 1
        }

        # Print the initial path
        echo "$exe_path"

        # Follow symlink chain
        local current_path="$exe_path"
        while [ -L "$current_path" ]; do
            # Resolve the symlink
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

            # Print the resolved path
            echo "$current_path"
        done
    }

    main "$@"
  '';
}
