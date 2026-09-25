{
  flake,
  pkgs,
  perSystem,
  ...
}: let
  file = "${pkgs.file}/bin/file";
  bat = "${pkgs.bat}/bin/bat";
in
  flake.lib.writeNushellApplication pkgs {
    name = "whichbinedit";
    # Absolute paths instead of runtimeInputs: prepending to PATH would shadow the executable being looked up
    source = ''
      def fail [msg: string] {
        print --stderr $"(ansi red_bold)error:(ansi reset) ($msg)"
        exit 1
      }

      def is-binary [path: string] {
        (^${file} --brief --mime-encoding --dereference $path | str trim) == "binary"
      }

      # Pick a file from an executable's symlink chain and open it in $EDITOR
      def main [
        name: string  # executable name to look up in PATH
        --hide-binaries  # leave binary files out of the picker
        --hide-symlinks  # leave symlinks out of the picker
        --text-only (-t)  # leave both binaries and symlinks out of the picker
      ] {
        let editor = $env.EDITOR? | default ""
        if ($editor | is-empty) {
          fail "EDITOR is not set"
        }

        let chain = ^${perSystem.self.whichbin}/bin/whichbin $name | lines | enumerate | each {|entry|
          let symlink = ($entry.item | path type) == "symlink"
          {index: $entry.index, path: $entry.item, symlink: $symlink, binary: (not $symlink and (is-binary $entry.item))}
        }
        # whichbin already printed why it failed
        if ($chain | is-empty) {
          exit 1
        }

        let candidates = $chain
          | where {|entry| not ($entry.binary and ($hide_binaries or $text_only)) }
          | where {|entry| not ($entry.symlink and ($hide_symlinks or $text_only)) }
        if ($candidates | is-empty) {
          fail "every file in the chain is hidden by the flags given"
        }

        let picked = if ($candidates | length) == 1 {
          $candidates | first
        } else {
          let preview = 'case "$(${file} -bL --mime-encoding {1})" in binary) ${file} -bL {1} ;; *) ${bat} --color=always --style=numbers {1} ;; esac'
          let line = $candidates
            | each {|entry|
              let label = if $entry.symlink {
                $"(ansi attr_dimmed)($entry.path)(ansi reset) (ansi yellow)\(symlink\)(ansi reset)"
              } else if $entry.binary {
                $"($entry.path) (ansi yellow)\(binary\)(ansi reset)"
              } else {
                $entry.path
              }
              $"($entry.path)\t($label)"
            }
            | str join "\n"
            | ^${pkgs.skim}/bin/sk --ansi --no-sort --delimiter '\t' --with-nth '2..' --preview $preview --preview-window up:60%
            | str trim
          if ($line | is-empty) {
            exit 1
          }
          let path = $line | split row "\t" | first
          $chain | where path == $path | first
        }

        # whichbin always ends on a non-symlink, so a symlink opens the next real file after it
        let choice = $chain | where {|entry| $entry.index >= $picked.index and not $entry.symlink } | first

        if $choice.binary {
          fail $"(ansi cyan)($choice.path)(ansi reset) is a binary file"
        }

        ^$editor $choice.path
      }
    '';
  }
