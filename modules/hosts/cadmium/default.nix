# cadmium — main development desktop (NixOS). Migrated from nix/hosts/cadmium/.
# Hardware, disks and the bootloader live in sibling files (also cadmium.nixos
# contributions); the user's niri monitor layouts live in ./niri.nix.
#
# Wiring (the simple rule): the host includes the NixOS feature aspects; the
# giodamelio user includes the Home-Manager feature aspects. The shared user
# baseline lives in modules/users/giodamelio.nix; cadmium-only user bits
# (groups, the sway/waybar desktop, agent tooling) attach here, on this host's
# user entity. Folded dual-class aspects (niri via the baseline, optnix below)
# attach to the user — den applies their `.nixos` half to the host
# automatically ("users shape their host").
{den, ...}: {
  # Declare the host (platform from the attr path) with its user and machine
  # role. The aspects named `cadmium` and `giodamelio` attach by convention.
  den.hosts.x86_64-linux.cadmium = {
    role = "desktop";
    ssh.hostKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFyDOEgsO9wykdbqhUOBWpSIXJ7Kd9D0Pl7W0dnxDn/m";

    users.giodamelio.ssh = {
      publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOKmSxFyT9n91A9dOpSCfl9kJj80KWFA6UvCtguT4S5b";
      accessTo.cesium.giodamelio = true;
    };
    # Per-host user wiring goes through the entity's `aspect` option (its
    # default is the bare den.aspects.giodamelio lookup; extra keys on the
    # entity itself are ignored freeform attrs), so the shared baseline must be
    # included explicitly here.
    users.giodamelio.aspect.includes = [
      # Shared baseline (modules/users/giodamelio.nix).
      den.aspects.giodamelio

      # Account details beyond the shared baseline. No primary-user here: it
      # would add the networkmanager group, which cadmium never had.
      {user.extraGroups = ["wheel" "docker" "sound" "dialout" "networkmanager"];}

      # cadmium-only Home-Manager features.
      den.aspects.qutebrowser
      den.aspects.hyprland
      den.aspects.wayvnc
      den.aspects.syncthing
      den.aspects.llm
      den.aspects.llm-tooling
      den.aspects.pi
      den.aspects.slack
      den.aspects.rss
      den.aspects.codex
      den.aspects.herdr
      den.aspects.tui-review
      den.aspects.camoufox

      # Folded dual-class: HM half here, NixOS half forwarded to the host.
      den.aspects.optnix
      den.aspects.kde-connect

      # Monitor layouts + media keybinds for niri (see ./niri.nix).
      den.aspects.cadmium-niri

      # cadmium-only Home-Manager settings (was home-configuration.nix).
      {
        homeManager = _: {
          # Setup fonts
          fonts = {
            fontconfig.enable = true;
          };
        };
      }
    ];
  };

  # ---- Host: NixOS feature aspects ----
  den.aspects.cadmium.includes = [
    den.aspects.wifi
    den.aspects.nh
    den.aspects.fonts
    den.aspects.onepassword
    den.aspects.yubikey
    den.aspects.remote-builder-builder
    den.aspects.nixbuild
    den.aspects.attic-client
    den.aspects.niks3-client
    den.aspects.basic-packages-desktop

    # Tools for programming with AI
    den.aspects.code-editing-ai
    den.aspects.ollama

    den.aspects.monitoring
    den.aspects.printing
    den.aspects."3d-printing"
    den.aspects.affinity
    den.aspects.signal
    den.aspects.todoist
    den.aspects.anytype
    den.aspects.zfs-backup

    # Software Development tools
    den.aspects.software-development
    den.aspects.embedded-development

    # Easy key rebinding
    den.aspects.keyd

    # den.aspects.rayfish # giopkgs build failing

    den.aspects.needlecast-server
  ];

  # ---- Host: cadmium-specific config (merges with the sibling files) ----
  den.aspects.cadmium.nixos = {pkgs, ...}: {
    # Gaming
    environment.systemPackages = [pkgs.discord];

    # Autosnapshot ZFS and send to NAS. tank/nix gets a shorter schedule below.
    gio.zfs_backup = {
      enable = true;
      datasets = [
        "tank/home"
        "tank/root"
      ];
    };

    # Short schedule for the reproducible Nix store; long retention pins GC'd
    # store paths and balloons disk usage.
    services.sanoid.datasets."tank/nix" = {
      hourly = 6;
      daily = 3;
      monthly = 0;
      yearly = 0;

      autosnap = true;
      autoprune = true;
    };

    # Aggressive short-lived snapshot schedule for ~/tmp
    services.sanoid.datasets."tank/giodamelio-tmp" = {
      frequently = 36;
      frequent_period = 10;
      hourly = 24;
      daily = 7;
      monthly = 1;
      yearly = 0;

      autosnap = true;
      autoprune = true;
    };

    # Cadmium uses programs.ssh.startAgent, which conflicts with
    # gcr-ssh-agent enabled by the niri-flake NixOS module.
    services.gnome.gcr-ssh-agent.enable = false;

    services.dbus.enable = true;
    xdg.portal = {
      enable = true;
      wlr.enable = true;
      extraPortals = with pkgs; [
        xdg-desktop-portal-gtk
      ];
    };
    services.displayManager = {
      ly.enable = true;
    };

    # Gaming
    programs.steam = {
      enable = true;
    };

    # Enable aarch64 emulation for cross-building RPi images
    boot.binfmt.emulatedSystems = ["aarch64-linux"];

    virtualisation.docker = {
      enable = true;
    };
    programs.ssh.startAgent = true;
    programs.mosh.enable = true;

    # Chasing intermittent multi-second freezes whenever a process does an NSS
    # lookup (user/group/host resolution) — the symptom of nsncd's fixed worker
    # pool wedging. Its 8-worker default is small, and once the pool is stuck
    # every lookup on the box blocks until the client gives up. More workers
    # widens the pool; the daily restart bounds how long a wedge can persist.
    systemd.services.nscd = {
      environment.NSNCD_WORKER_COUNT = "32";
      serviceConfig.RuntimeMaxSec = "1d";
      # NSNCD_HANDOFF_TIMEOUT belongs in serviceConfig.Environment, not here:
      # nixpkgs pins it to 10 there, and that section is rendered last, so it
      # would silently override anything set in `environment`. Lowering it to 3
      # would not stop a wedge, only shorten the stall before glibc falls back.
    };

    # Send Cargo build artifacts to the unsnapshotted tank/giodamelio-build
    # dataset (mounted at ~/.cache/builds) so target/ churn never lands in home
    # snapshots. Set at the PAM session level (not home.sessionVariables) so it
    # reaches every shell, including nushell, regardless of shell type.
    environment.sessionVariables.CARGO_TARGET_DIR = "/home/giodamelio/.cache/builds/cargo";

    networking.hostId = "3c510ad9";

    services.resolved.enable = true;
    # resolved owns /etc/resolv.conf, so NetworkManager has to push DNS to it
    # over D-Bus instead of writing the file itself.
    networking.networkmanager.dns = "systemd-resolved";

    # The 26.11 default, opted into early. When false, ZFS refuses to import a
    # pool still marked as in use by another system (hostid mismatch) instead of
    # forcing it — which prevents two hosts writing the same pool and corrupting
    # it (e.g. after a disk moves or an unclean shutdown leaves the pool held).
    boot.zfs.forceImportRoot = false;

    nixpkgs.config.allowUnfree = true;

    system.stateVersion = "25.11";
  };
}
