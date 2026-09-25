{inputs, ...}: {
  den.aspects.nixpkgs-multiverse.nixos = {pkgs, ...}: let
    # perSystem.multiverse.mvs would bootstrap its own nixpkgs release; build it on ours instead.
    inherit (pkgs.extend inputs.multiverse.overlays.default) mvs;

    # nix-locate deliberately comes from PATH so it matches the user's own nix-index database.
    comma-script = inputs.self.lib.writeNushellApplication pkgs {
      name = "comma";
      runtimeInputs = [mvs pkgs.skim];
      source = ''
        const mvs_flags = ["--eval" "--dry-run"]

        def usage [text: string] {
          print --stderr $text
          exit 2
        }

        def resolve-bin [bin: string] {
          let out = (nix-locate --minimal --at-root --whole-name $"/bin/($bin)")
          # Parenthesised attrs only depend on the package that ships the file.
          let attrs = $out
            | lines
            | where {|l| not ($l starts-with "(") }
            | each {|l| $l | str replace --regex '\.[^.]+$' "" }
            | sort
            | uniq
          match ($attrs | length) {
            0 => { error make --unspanned {msg: $"no package provides bin/($bin)"} }
            1 => { $attrs | first }
            _ => {
              $attrs | pick $"($bin)> " "mvs query gone {}; echo; mvs size {}; echo; mvs query versions {} | tail -n 20"
            }
          }
        }

        def pick [prompt: string, preview: string] {
          let choices = $in
          # Raising inside catch would chain sk's exit error onto ours, so decide outside it.
          let result = try {
            {choice: ($choices | str join "\n" | sk --prompt $prompt --preview $preview --preview-window up:50% | str trim)}
          } catch {|e| {error: $e} }
          if "choice" in $result { return $result.choice }
          if $result.error.exit_code? == 130 {
            error make --unspanned {msg: "nothing selected"}
          }
          error make --unspanned {msg: $result.error.msg}
        }

        # NAME[@VER] -> ATTR[@VER]; NAME is tried as an attribute first, then as a binary.
        def resolve-spec [spec: string] {
          let name = $spec | str replace --regex '@.*' ""
          let ver = $spec | str replace --regex '^[^@]*' ""
          if (mvs query versions $name | complete).exit_code == 0 {
            $spec
          } else {
            $"(resolve-bin $name)($ver)"
          }
        }

        def run-comma [args: list<string>] {
          let text = "usage: , [--eval|--dry-run] <binary>[@version] [args...]"
          let flags = $args | take while {|a| $a in $mvs_flags }
          let rest = $args | skip ($flags | length)
          if ($rest | is-empty) or ($rest.0 in ["-h" "--help"]) { usage $text }
          let bin = $rest.0 | str replace --regex '@.*' ""
          let ver = $rest.0 | str replace --regex '^[^@]*' ""
          exec mvs shell ...$flags $"(resolve-bin $bin)($ver)" -- $bin ...($rest | skip 1)
        }

        def run-shell [args: list<string>] {
          let text = "usage: ,s [--eval|--dry-run] <attr-or-binary>[@version]... [-- cmd args...]"
          let split = $args | enumerate | where item == "--" | get -o 0.index
          let before = if $split == null { $args } else { $args | first $split }
          let cmd = if $split == null { [] } else { $args | skip ($split + 1) }
          if ($before | any {|a| $a in ["-h" "--help"] }) { usage $text }
          let flags = $before | where {|a| $a in $mvs_flags }
          let specs = $before | where {|a| $a not-in $mvs_flags } | each {|s| resolve-spec $s }
          if ($specs | is-empty) { usage $text }
          if ($env.SHELL? | is-empty) { error make --unspanned {msg: "SHELL is not set"} }
          let cmd = if ($cmd | is-empty) { [$env.SHELL] } else { $cmd }
          exec mvs shell ...$flags ...$specs -- ...$cmd
        }

        def run-shell-version [args: list<string>] {
          let text = "usage: ,sv [--eval|--dry-run] <attr-or-binary> [<attr-or-binary>[@version]...] [-- cmd args...]"
          let flags = $args | take while {|a| $a in $mvs_flags }
          let rest = $args | skip ($flags | length)
          if ($rest | is-empty) or ($rest.0 in ["-h" "--help"]) or ($rest.0 | str contains "@") { usage $text }
          let attr = resolve-spec $rest.0
          let rows = mvs --json query versions $attr
            | from json
            | get versions
            | reverse
            | each {|v|
              let last = if $v.current { "current" } else { $v.last }
              $"($v.version | fill --width 20) ($v.first) .. ($last)"
            }
          let version = $rows
            | pick $"($attr)@" $"mvs query when ($attr) {1}; echo; mvs size ($attr)@{1}"
            | split row " "
            | first
          run-shell [...$flags $"($attr)@($version)" ...($rest | skip 1)]
        }

        # $env is case-insensitive, so a devshell's lowercase `shell` (stdenv's bash)
        # clobbers SHELL at startup; the untouched value is still in our environ.
        def original-shell [] {
          open --raw $"/proc/($nu.pid)/environ"
            | decode utf-8
            | split row (char nul)
            | where {|e| $e starts-with "SHELL=" }
            | each {|e| $e | str substring 6.. }
            | get -o 0
        }

        def run-versions [args: list<string>] {
          let text = "usage: ,v <pkg>                     every version of <pkg>
               ,v when <pkg> <version>      when a version was in nixpkgs
               ,v gone <pkg>                last sighting, or still current
               ,v at <selector> <pkg>       version shipped at a release/date/commit
               ,v rev|search|diff|stats ... passthrough to `mvs query`
               ,v path|size|deps|rdeps <pkg>[@version]
               ,v identify|solve|lock ...   passthrough to `mvs`
        <pkg> may be an attribute or a binary name (resolved via nix-locate)."
          let sub = $args | get -o 0
          match $sub {
            null | "-h" | "--help" => { usage $text }
            "when" | "gone" => {
              if ($args | length) < 2 { usage $text }
              exec mvs query $sub (resolve-spec $args.1) ...($args | skip 2)
            }
            "at" => {
              if ($args | length) < 3 { usage $text }
              exec mvs query at $args.1 (resolve-spec $args.2) ...($args | skip 3)
            }
            "rev" | "search" | "diff" | "stats" => { exec mvs query ...$args }
            "path" | "size" | "deps" | "rdeps" => {
              if ($args | length) < 2 { usage $text }
              exec mvs $sub (resolve-spec $args.1) ...($args | skip 2)
            }
            "identify" | "solve" | "lock" => { exec mvs ...$args }
            _ => { exec mvs query versions (resolve-spec $sub) ...($args | skip 1) }
          }
        }

        def --wrapped main [...args: string] {
          let shell = original-shell
          if $shell != null { $env.SHELL = $shell }
          match ($env.CURRENT_FILE | path basename) {
            "," | "comma" => { run-comma $args }
            ",s" => { run-shell $args }
            ",sv" => { run-shell-version $args }
            ",v" => { run-versions $args }
            $name => { error make --unspanned {msg: $"unknown invocation name: ($name)"} }
          }
        }
      '';
    };

    # Store path names can't contain ",", so the script is named comma and linked under the short names.
    comma = pkgs.runCommand "comma" {} ''
      mkdir -p $out/bin
      ln -s ${comma-script}/bin/comma $out/bin/comma
      for name in , ,s ,sv ,v; do
        ln -s comma "$out/bin/$name"
      done
    '';
  in {
    imports = [inputs.multiverse.nixosModules.default];

    multiverse = {
      enable = true;
      config.allowUnfree = true;
    };

    environment.systemPackages = [mvs comma];
  };
}
