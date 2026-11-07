{
  pkgs,
  inputs,
  perSystem,
  ...
}: let
  jail = import ../lib/jail-combinators.nix {inherit pkgs inputs;};
  claudeCode = perSystem.llm-agents.claude-code;
  kache = perSystem.kache.kache;
  # Paths as seen inside the jail; the store and runtime dir land under the
  # host's ~/.cache/builds/jail.
  kacheConfig = (pkgs.formats.toml {}).generate "kache-jail.toml" {
    cache = {
      local_store = "/home/giodamelio/.cache/builds/kache";
      runtime_dir = "/home/giodamelio/.cache/builds/kache-run";
      readonly_store = "/kache-host";
      # bwrap sets NoNewPrivs, which otherwise blocks delegating to the jail's own daemon.
      trust_daemon_execution = true;
    };
  };
in
  # jail.nix interpolates Linux-only packages (shadow) at eval time, so calling
  # it on Darwin throws before Blueprint can filter on meta.platforms.
  if pkgs.stdenv.hostPlatform.isLinux
  then
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
        # Only the jail's own slice of the builds disk, so it can neither read
        # nor plant artifacts in target dirs or caches the host trusts.
        (add-runtime ''
          mkdir -p "$HOME/.cache/builds/jail"
          RUNTIME_ARGS+=(--bind "$HOME/.cache/builds/jail" "$HOME/.cache/builds")
        '')
        # Read-only so SQLite cannot create side files in the host's store.
        (add-runtime ''
          RUNTIME_ARGS+=(--ro-bind-try "$HOME/.cache/builds/kache" /kache-host)
        '')
        (try-readwrite (noescape "~/.cache/claude-cli-nodejs"))
        (try-readwrite (noescape "~/.local/state/claude"))
        # agent-dms notify toggle and unread cache, shared with the host CLI.
        (add-runtime ''
          mkdir -p "$HOME/.local/state/agent-dms"
          RUNTIME_ARGS+=(--bind "$HOME/.local/state/agent-dms" "$HOME/.local/state/agent-dms")
        '')
        (try-readwrite (noescape "~/.local/share/tuicr"))
        (try-readwrite (noescape "~/Documents/life/Projects/"))
        (try-readwrite (noescape "~/projects/browser-use/browser-harness"))
        # Scratch dirs so nvf can start when editing the prompt in $EDITOR
        (add-runtime ''
          RUNTIME_ARGS+=(--tmpfs "$HOME/.local/share/nvf" --tmpfs "$HOME/.local/state/nvf")
        '')

        # Claude-specific ro paths
        (try-readonly "/etc/nix")
        (try-readonly "/usr/bin/env")
        (try-readonly (noescape "~/.gitconfig"))
        (try-readonly (noescape "~/.config/git"))
        (try-readonly (noescape "~/.config/jj"))
        (try-readonly (noescape "~/.config/nix"))
        (try-readonly (noescape "~/.local/share/gh/extensions"))
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
        agent-dms-token
        github-token
        (try-readwrite "/run/user/1000/herdr-proxy.sock")
        (set-env "HERDR_SOCKET_PATH" "/run/user/1000/herdr-proxy.sock")
        (set-env "CLAUDE_CODE_NO_FLICKER" "1")
        (set-env "RUSTC_WRAPPER" (pkgs.lib.getExe kache))
        (set-env "KACHE_CONFIG" "${kacheConfig}")
        # Empty disables the host layer, so the global /etc/kache/config.toml is ignored.
        (set-env "KACHE_HOST_CONFIG" "")
        # Claude saves .claude.json via temp file + rename(), which fails with
        # EBUSY on the single-file ~/.claude.json bind, so keep it inside ~/.claude.
        (add-runtime ''
          RUNTIME_ARGS+=(--setenv CLAUDE_CONFIG_DIR "$HOME/.claude")
        '')

        # Pass --dangerously-skip-permissions before user args
        (extra-args ["--dangerously-skip-permissions"])

        readonly-home
      ])
  else {meta.platforms = pkgs.lib.platforms.linux;}
