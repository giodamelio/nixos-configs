{
  pkgs,
  inputs,
  perSystem,
  ...
}: let
  jail = import ../lib/jail-combinators.nix {inherit pkgs inputs;};
  claudeCode = perSystem.llm-agents.claude-code;
in
  jail "jailed-claude" claudeCode (c:
    with c; [
      # NixOS essentials
      network
      (readwrite "/nix")
      (try-readonly "/run")
      (try-readonly "/etc/static")
      (try-readonly "/etc/profiles")
      overlay-home

      # Claude-specific rw paths
      (try-readwrite (noescape "~/.claude"))
      (try-readwrite (noescape "~/.claude.json"))
      (try-readwrite (noescape "~/.config/claude"))
      (try-readwrite (noescape "~/.cache/claude"))
      (try-readwrite (noescape "~/.cache/claude-cli-nodejs"))
      (try-readwrite (noescape "~/.local/state/claude"))
      (try-readwrite (noescape "~/Documents/life/Projects/"))

      # Claude-specific ro paths
      (try-readonly "/etc/nix")
      (try-readonly "/usr/bin/env")
      (try-readonly (noescape "~/.gitconfig"))
      (try-readonly (noescape "~/.config/git"))
      (try-readonly (noescape "~/.config/jj"))
      (try-readonly (noescape "~/.config/nix"))
      (try-readonly (noescape "~/projects/giodamelio/agent-skills"))

      # CWD bind must come after ro paths so it wins when they overlap
      work-in-cwd
      (rw-paths-from-file ".sandbox-paths")

      # Environment
      (unset-env "ANTHROPIC_API_KEY")

      # Pass --dangerously-skip-permissions before user args
      (extra-args ["--dangerously-skip-permissions"])
    ])
