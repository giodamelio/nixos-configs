{pkgs, ...}:
pkgs.writeShellApplication {
  name = "whichbin";
  text = ''
    # whichbin - Find executables in PATH and follow symlink and wrapper chains
    # Usage: whichbin <executable_name>

    set -euo pipefail

    # Absolute paths instead of runtimeInputs: prepending to PATH would shadow the executable being looked up
    readlink=${pkgs.coreutils}/bin/readlink
    dirname=${pkgs.coreutils}/bin/dirname
    tail=${pkgs.coreutils}/bin/tail
    grep=${pkgs.gnugrep}/bin/grep

    # Target of a makeWrapper-style shell wrapper, from its final exec line
    wrapped_target() {
        local line
        line=$("$grep" -IE '^exec ' "$1" | "$tail" -n 1) || return 1
        # shellcheck disable=SC2016 # literal $0 in the wrapper's exec -a
        local re='^exec (-a "\$0" +)?"?(/nix/store/[^" ]+)'
        [[ "$line" =~ $re ]] || return 1
        echo "''${BASH_REMATCH[2]}"
    }

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

        # Follow symlink and wrapper chain
        local current_path="$exe_path"
        local target
        while true; do
            if [ -L "$current_path" ]; then
                # Resolve the symlink
                target=$("$readlink" "$current_path")

                # If target is relative, resolve it relative to the symlink's directory
                if [[ "$target" != /* ]]; then
                    local current_dir
                    current_dir=$("$dirname" "$current_path")
                    current_path="$current_dir/$target"
                else
                    current_path="$target"
                fi
            elif target=$(wrapped_target "$current_path"); then
                current_path="$target"
            else
                break
            fi

            # Print the resolved path
            echo "$current_path"
        done
    }

    main "$@"
  '';
}
