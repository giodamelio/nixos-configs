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
      # NixOS essentials. /run is not bound: read-only mounts do not stop
      # connect(), so every socket in it (session bus, ssh-agent) would be live.
      network
      (readonly "/nix/store")
      untrusted-nix-daemon
      (try-readonly "/run/current-system")
      (try-readonly "/etc/static")
      (try-readonly "/etc/profiles")
      private-cache
      # Host ~/.cargo would be a jail escape (config.toml wrappers, bin/,
      # unverified extracted registry sources), so keep a private one.
      (add-runtime ''
        RUNTIME_ARGS+=(--setenv CARGO_HOME "$HOME/.cache/cargo")
      '')

      # Claude-specific rw paths
      (try-readwrite (noescape "~/.claude"))
      (try-readwrite (noescape "~/.claude.json"))
      (try-readwrite (noescape "~/.config/claude"))
      (try-readwrite (noescape "~/.cache/claude"))
      (try-readwrite (noescape "~/.cache/builds"))
      (try-readwrite (noescape "~/.cache/claude-cli-nodejs"))
      (try-readwrite (noescape "~/.local/state/claude"))
      (try-readwrite (noescape "~/.local/share/tuicr"))
      (try-readwrite (noescape "~/Documents/life/Projects/"))
      (try-readwrite (noescape "~/projects/browser-use/browser-harness"))

      # Claude-specific ro paths
      (try-readonly "/etc/nix")
      (try-readonly "/usr/bin/env")
      (try-readonly (noescape "~/.gitconfig"))
      (try-readonly (noescape "~/.config/git"))
      (try-readonly (noescape "~/.config/jj"))
      (try-readonly (noescape "~/.config/nix"))
      (try-readonly (noescape "~/projects/giodamelio/agent-skills"))
      (try-readonly (noescape "~/.config/google-chrome/DevToolsActivePort"))

      # CWD bind must come after ro paths so it wins when they overlap
      work-in-cwd

      bind-jj-workspace-store

      # Allow adding other paths to the sandbox for cross repo work
      (rw-paths-from-file ".sandbox-paths")

      # Drop --new-session: setsid() detaches from the controlling terminal so
      # the kernel never delivers SIGWINCH and claude renders at a stale width.
      # The flag only guards TIOCSTI input injection, already blocked by the
      # kernel (dev.tty.legacy_tiocsti = 0 on 6.2+).
      no-new-session

      # Environment
      (unset-env "ANTHROPIC_API_KEY")
      (unset-env "DBUS_SESSION_BUS_ADDRESS")
      (unset-env "SSH_AUTH_SOCK")
      veans-token
      (try-readwrite "/run/user/1000/herdr-proxy.sock")
      (set-env "HERDR_SOCKET_PATH" "/run/user/1000/herdr-proxy.sock")
      (set-env "CLAUDE_CODE_NO_FLICKER" "1")

      # Pass --dangerously-skip-permissions before user args
      (extra-args ["--dangerously-skip-permissions"])

      readonly-home
    ])
