# claude-code — the programs.gio-claude-code option set: a jailed `claude`
# wrapper plus optional agent/command symlinks. Converted from
# nix/modules/home/claude-code/default.nix.
#   - `flake.packages.<sys>.jailed-claude` -> `perSystem.self.jailed-claude`.
#   - `perSystem.llm-agents.{claude-code,rtk}` are module args from the
#     per-system aspect.
#
# The example agent/command markdown lives in ./agents and ./commands; a host
# only gets them when it sets `programs.gio-claude-code.agents` / `.commands`
# (cesium doesn't; calcium references them by relative path).
{inputs, ...}: {
  den.aspects.claude-code.homeManager = {
    config,
    lib,
    pkgs,
    perSystem,
    ...
  }: let
    jailedClaude = perSystem.self.jailed-claude;
    claudeCode = perSystem.llm-agents.claude-code;

    # No-operand `rtk read` (what the hook rewrites a bare cat/head/tail into)
    # crash-exits 127 instead of reading stdin like cat. Patch reads stdin.
    # REMIND-ME-TO: Drop rtk-read-stdin.patch issue_closed=github:rtk-ai/rtk#2095
    rtk = perSystem.llm-agents.rtk.overrideAttrs (old: {
      patches = (old.patches or []) ++ [./rtk-read-stdin.patch];
    });

    # Wrap jailed-claude so it's also available as "claude" in PATH
    claudeWrapper = pkgs.symlinkJoin {
      name = "claude-wrapper";
      paths = [jailedClaude];
      postBuild = ''
        ln -s ${lib.getExe jailedClaude} $out/bin/claude
        # Also put the original (non-jailed) one in PATH as "claude-original"
        ln -s ${lib.getExe claudeCode} $out/bin/claude-original
      '';
    };

    # SDK sessions (Claudian, `claude -p`) are hidden from `claude --resume`'s picker.
    claude-resume-sdk-sessions = inputs.self.lib.writeNushellApplication pkgs {
      name = "claude-resume-sdk-sessions";
      runtimeInputs = [pkgs.ripgrep pkgs.skim];
      source = ''
        # The jsonl format is internal to Claude Code, so strict `get` makes a
        # format change fail loudly instead of silently dropping sessions.
        def session-info [file: path] {
          let records = open --raw $file | from json --objects
          let messages = $records | where type in [user assistant]
          if ($messages | is-empty) { return null }
          let last = $messages | last
          let titles = $records | where type == ai-title
          let prompts = $records | where type == last-prompt
          let title = if not ($titles | is-empty) {
            $titles | last | get aiTitle
          } else if not ($prompts | is-empty) {
            $prompts | last | get lastPrompt
          } else {
            "untitled"
          }
          {
            updated: ($last | get timestamp | into datetime)
            entrypoint: ($last | get entrypoint)
            title: $title
            cwd: ($last | get cwd)
            id: ($last | get sessionId)
            file: $file
          }
        }

        def message-text [content: any] {
          if ($content | describe) == string { return $content }
          $content
          | each {|block|
            match ($block | get type) {
              text => ($block | get text)
              tool_use => $"[tool: ($block | get name)]"
              _ => null
            }
          }
          | compact
          | str join "\n"
        }

        def "main preview" [file: path] {
          open --raw $file
          | from json --objects
          | where type in [user assistant]
          | where {|r| not ($r.isMeta? | default false) }
          | each {|r|
            let text = message-text ($r | get message.content) | str trim
            if ($text | is-empty) { return null }
            let role = if $r.type == user { $"(ansi green)you(ansi reset)" } else { $"(ansi cyan)claude(ansi reset)" }
            $"($role): ($text)"
          }
          | compact
          | last 30
          | str join "\n\n"
        }

        def sdk-sessions [] {
          let projects = $nu.home-dir | path join .claude projects
          let found = ^rg --files-with-matches --fixed-strings --glob '*.jsonl' '"entrypoint":"sdk' $projects | complete
          if $found.exit_code == 1 { return [] }
          if $found.exit_code != 0 { error make {msg: $"rg failed: ($found.stderr)"} }
          $found.stdout
          | lines
          | each {|f| session-info $f }
          | where {|s| $s.entrypoint | str starts-with sdk }
          | sort-by updated --reverse
        }

        # Defaults to the current directory, matching `claude --resume`.
        def main [--all (-a)] {
          let sessions = if $all { sdk-sessions } else { sdk-sessions | where cwd == $env.PWD }
          if ($sessions | is-empty) {
            error make {msg: (if $all { "no sdk sessions found" } else { $"no sdk sessions in ($env.PWD), use --all to see every directory" })}
          }

          let picked = try {
            $sessions
            | each {|s|
              let title = $s.title | str replace --all --regex '\s+' ' '
              [($s.updated | format date '%Y-%m-%d %H:%M') $s.entrypoint $title $s.cwd $s.id $s.file] | str join "\t"
            }
            | str join "\n"
            | ^sk --no-sort --delimiter '\t' --with-nth '1..4' --preview-window 'up:60%:wrap' --preview $"'($env.CURRENT_FILE)' preview {6}"
          } catch {
            if $env.LAST_EXIT_CODE in [1 130] { exit 0 }
            error make {msg: $"sk exited with ($env.LAST_EXIT_CODE)"}
          }

          let fields = $picked | str trim --right --char "\n" | split row "\t"
          let cwd = $fields | get 3
          let id = $fields | get 4
          if not ($cwd | path exists) { error make {msg: $"session cwd no longer exists: ($cwd)"} }
          cd $cwd
          exec claude --resume $id
        }
      '';
    };
  in {
    options.programs.gio-claude-code = {
      enable = lib.mkEnableOption "Claude Code configuration management";

      installPackage = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Whether to install the Claude Code package";
      };

      agents = lib.mkOption {
        type = lib.types.attrsOf lib.types.path;
        default = {};
        description = "Agent markdown files to symlink (name -> path)";
        example = lib.literalExpression ''
          {
            postgres-db-expert = ./agents/postgres-db-expert.md;
            my-custom-agent = ./agents/my-custom-agent.md;
          }
        '';
      };

      commands = lib.mkOption {
        type = lib.types.attrsOf (lib.types.either lib.types.path (lib.types.attrsOf lib.types.path));
        default = {};
        description = "Command files to symlink";
        example = lib.literalExpression ''
          {
            plan-save = ./commands/plan-save.md;
            pre-commit = {
              markdown = ./commands/pre-commit.md;
              script = ./commands/pre-commit.sh;
            };
          }
        '';
      };
    };

    config = lib.mkIf config.programs.gio-claude-code.enable {
      home.packages = [
        claudeWrapper
        rtk
        claude-resume-sdk-sessions
      ];

      home.shellAliases = {
        claude = lib.getExe jailedClaude;
        claude-dangerous = lib.getExe claudeCode;
      };

      # Untrusted nix-daemon for jailed agents (see untrusted-nix-daemon in
      # nix/lib/jail-combinators.nix). --force-untrusted only takes effect with
      # --process-ops; without it the connection is spliced to the real,
      # trusted daemon.
      systemd.user.sockets.nix-daemon-untrusted = {
        Unit.Description = "Untrusted nix-daemon proxy for jailed agents";
        Socket = {
          ListenStream = "%t/nix-daemon-untrusted.sock";
          SocketMode = "0600";
          Accept = true;
        };
        Install.WantedBy = ["sockets.target"];
      };

      systemd.user.services."nix-daemon-untrusted@" = {
        Unit.Description = "Untrusted nix-daemon proxy connection";
        Service = {
          ExecStart = "${lib.getExe pkgs.nix} --extra-experimental-features 'daemon-trust-override mounted-ssh-store' daemon --stdio --force-untrusted --process-ops";
          StandardInput = "socket";
          StandardOutput = "socket";
          StandardError = "journal";
        };
      };

      # Dynamically link agents and commands using home.file
      home.file =
        {
          # settings.json stays mutable (Claude Code rewrites it), so link the
          # path its statusLine.command already points at.
          ".claude/statusline-command.sh".source = lib.getExe perSystem.self.claude-statusline;
        }
        //
        # Link agents
        lib.mapAttrs' (
          name: path: lib.nameValuePair ".claude/agents/${name}.md" {source = path;}
        )
        config.programs.gio-claude-code.agents
        //
        # Link commands (handle both simple paths and attrsets with markdown/script)
        lib.concatMapAttrs (
          name: value:
            if lib.isPath value
            then {
              ".claude/commands/${name}.md" = {
                source = value;
              };
            }
            else
              lib.optionalAttrs (value ? markdown) {
                ".claude/commands/${name}.md" = {
                  source = value.markdown;
                };
              }
              // lib.optionalAttrs (value ? script) {
                ".claude/commands/${name}.sh" = {
                  source = value.script;
                  executable = true;
                };
              }
        )
        config.programs.gio-claude-code.commands;
    };
  };
}
