# pi — the pi/omp LLM agents wrapped in a bubblewrap jail (jail.nix), with
# -dangerous escape hatches. Converted from nix/modules/home/pi.nix. The jail
# combinator library is a plain file import shared with Blueprint.
{inputs, ...}: {
  den.aspects.pi.homeManager = {
    lib,
    pkgs,
    perSystem,
    ...
  }: let
    jail = import ../../../nix/lib/jail-combinators.nix {inherit pkgs inputs;};
    inherit (perSystem.llm-agents) pi omp;
    # inherit (perSystem.giopkgs) omp;

    commonPermissions = c:
      with c; [
        # NixOS essentials
        network
        (readonly "/nix/store")
        untrusted-nix-daemon
        (try-readonly "/run/current-system")
        (try-readonly "/etc/static")
        (try-readonly "/etc/profiles")
        private-cache
        work-in-cwd
        bind-jj-workspace-store
        (rw-paths-from-file ".sandbox-paths")

        # Shared ro paths
        (try-readonly "/etc/nix")
        (try-readonly "/usr/bin/env")
        (try-readonly (noescape "~/.gitconfig"))
        (try-readonly (noescape "~/.config/git"))
        (try-readonly (noescape "~/.config/jj"))
        (try-readonly (noescape "~/.config/nix"))
        (try-readonly (noescape "~/projects/giodamelio/agent-skills"))
        (try-readonly (noescape "~/projects/nixos-configs"))

        # Shared rw paths
        (try-readwrite (noescape "~/Documents/life/Projects/"))
        (try-readwrite (noescape "~/.omp"))
        (try-readwrite (noescape "~/.config/omp"))
        (try-readwrite (noescape "~/.pi"))
        (try-readwrite (noescape "~/.config/pi"))

        # Environment
        (unset-env "ANTHROPIC_API_KEY")
        (unset-env "DBUS_SESSION_BUS_ADDRESS")
        (unset-env "SSH_AUTH_SOCK")

        readonly-home
      ];

    jailedPi = jail "jailed-pi" pi commonPermissions;
    jailedOmp = jail "jailed-omp" omp commonPermissions;
  in {
    home.packages = [
      jailedPi
      jailedOmp
    ];

    home.shellAliases = {
      pi = lib.getExe jailedPi;
      pi-dangerous = lib.getExe pi;
      omp = lib.getExe jailedOmp;
      omp-dangerous = lib.getExe omp;
    };
  };
}
