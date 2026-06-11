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
{
  inputs,
  den,
  ...
}: let
  inherit (inputs.self.lib.homelab.machines.cadmium) monitor-names;
in {
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
      {user.extraGroups = ["wheel" "docker" "sound"];}

      # cadmium-only Home-Manager features.
      den.aspects.qutebrowser
      den.aspects.hyprland
      den.aspects.sway # pulls in vicinae
      den.aspects.waybar
      den.aspects.wayvnc
      den.aspects.syncthing
      den.aspects.llm
      den.aspects.pi
      den.aspects.slack
      den.aspects.rss
      den.aspects.codex

      # Folded dual-class: HM half here, NixOS half forwarded to the host.
      den.aspects.optnix

      # Monitor layouts + media keybinds for niri (see ./niri.nix).
      den.aspects.cadmium-niri

      # cadmium-only Home-Manager settings (was home-configuration.nix).
      {
        homeManager = {perSystem, ...}: {
          # Configure waybar for sway
          gio.waybar = {
            enable = true;
            windowManager = "sway";
            fontSize = 20;
            package = perSystem.giopkgs.waybar;
            audioOutputSwitcher = true;
            modules = {
              left = ["sway/mode" "sway/workspaces"];
              right = ["network" "network-graphs" "cpu" "memory" "custom/claude-usage" "pulseaudio" "tray" "custom/notification" "clock" "custom/power"];
            };
            monitors = {
              main = monitor-names.middle;
              secondary = [monitor-names.left monitor-names.right];
            };
            networkInterfaces = [
              {name = "enp0*";}
            ];
          };

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
    # The homelab SSH certificate authority lives here.
    den.aspects.ssh-ca

    den.aspects.wifi
    den.aspects.nh
    den.aspects.fonts
    den.aspects.onepassword
    den.aspects.remote-builder-builder
    den.aspects.client-mtls
    den.aspects.attic-client
    den.aspects.basic-packages-desktop

    # Tools for programming with AI
    den.aspects.code-editing-ai
    den.aspects.ollama

    den.aspects.monitoring
    den.aspects.printing
    den.aspects.affinity
    den.aspects.signal
    den.aspects.zfs-backup

    # Software Development tools
    den.aspects.software-development
    den.aspects.embedded-development

    # Easy key rebinding
    den.aspects.keyd
  ];

  # ---- Host: cadmium-specific config (merges with the sibling files) ----
  den.aspects.cadmium.nixos = {pkgs, ...}: {
    # 3D printing (was cadmium/3d-printing.nix)
    environment.systemPackages = with pkgs; [
      orca-slicer

      # Gaming
      discord
    ];

    # Autosnapshot ZFS and send to NAS
    gio.zfs_backup = {
      enable = true;
      datasets = [
        "tank/home"
        "tank/nix"
        "tank/root"
      ];
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

    # Sway session beside niri (was inline in configuration.nix)
    programs.sway = {
      enable = true;
      wrapperFeatures.gtk = true;
    };
    services.dbus.enable = true;
    xdg.portal = {
      enable = true;
      wlr.enable = true;
      extraPortals = with pkgs; [
        xdg-desktop-portal-gtk
      ];
    };
    services.displayManager = {
      sessionPackages = [
        pkgs.sway
      ];
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

    networking.hostId = "3c510ad9";

    nixpkgs.config.allowUnfree = true;

    system.stateVersion = "25.11";
  };
}
