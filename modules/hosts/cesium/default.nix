# cesium — Chromebook travel laptop (NixOS). First den host with a Home-Manager
# user. Migrated from nix/hosts/cesium/. Hardware lives in ./hardware.nix (also
# a cesium.nixos contribution).
#
# Wiring (the simple rule): the host includes the NixOS feature aspects; the
# giodamelio user includes the Home-Manager feature aspects. The shared user
# baseline lives in modules/users/giodamelio.nix; only cesium-specific user
# bits (primary-user/networkmanager, audio group, zed-editor, kde-connect) are
# attached here, on this host's user entity. Folded dual-class aspects
# (niri, kde-connect) attach to the user — den applies their `.nixos` half to
# the host automatically ("users shape their host").
#
# Dropped vs Blueprint: nix/hosts/cesium/remote-wayland-cadmium.nix (the
# waypipe-to-cadmium second-niri session) is intentionally not ported.
{den, ...}: {
  # Declare the host (platform from the attr path) with its user and machine
  # role. The aspects named `cesium` and `giodamelio` attach by convention.
  den.hosts.x86_64-linux.cesium = {
    role = "desktop";
    ssh.hostKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIK5LTFNDeaPXdAFvl265BWiiu/UAS6q1CfgdutsYYyC8";
    users.giodamelio.ssh = {
      publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJwxJI1kvYY7wN9ps8W23kadHiqX8d/BJT/zI9oh0uDp";
      accessTo.cadmium.giodamelio = true;
    };
    # Per-host user wiring goes through the entity's `aspect` option (its
    # default is the bare den.aspects.giodamelio lookup; extra keys on the
    # entity itself are ignored freeform attrs), so the shared baseline must be
    # included explicitly here.
    users.giodamelio.aspect.includes = [
      # Shared baseline (modules/users/giodamelio.nix).
      den.aspects.giodamelio

      den.batteries.primary-user # wheel + networkmanager

      # Account details beyond the shared baseline.
      {user.extraGroups = ["audio"];} # merges with wheel+networkmanager from primary-user

      # cesium-only Home-Manager features.
      den.aspects.zed-editor
      den.aspects.herdr

      # Folded dual-class: HM half here, NixOS half forwarded to the host.
      den.aspects.kde-connect
    ];
  };

  # ---- Host: NixOS feature aspects ----
  den.aspects.cesium.includes = [
    den.aspects.wifi
    den.aspects.nh
    den.aspects.optnix
    den.aspects.basic-packages-desktop
    den.aspects.onepassword
    den.aspects.fonts
    den.aspects.remote-builder-user
    den.aspects.attic-client
    den.aspects.pipewire
    den.aspects.battery-optimization
    den.aspects.software-development
  ];

  # ---- Host: cesium-specific config (merges with ./hardware.nix) ----
  den.aspects.cesium.nixos = {
    perSystem,
    pkgs,
    ...
  }: {
    # On-screen keyboard + Chromebook keyboard remapping (was cesium/niri.nix).
    environment.systemPackages = [
      pkgs.wvkbd
      perSystem.giopkgs.emdash # Random software
    ];

    services.keyd = {
      enable = true;
      keyboards.default = {
        ids = ["*"];
        settings = {
          main = {
            # Top row: map F-keys to Chromebook media functions
            f1 = "back";
            f2 = "forward";
            f3 = "refresh";
            f4 = "zoom"; # fullscreen
            f5 = "scale"; # overview
            f6 = "brightnessdown";
            f7 = "brightnessup";
            f8 = "mute";
            f9 = "volumedown";
            f10 = "volumeup";
          };
          # Search + top row = actual F-keys
          meta = {
            f1 = "f1";
            f2 = "f2";
            f3 = "f3";
            f4 = "f4";
            f5 = "f5";
            f6 = "f6";
            f7 = "f7";
            f8 = "f8";
            f9 = "f9";
            f10 = "f10";
          };
          # Search + Shift + key = missing keys (keeps Mod+arrows free for Niri)
          "meta+shift" = {
            backspace = "delete";
            up = "pageup";
            down = "pagedown";
            left = "home";
            right = "end";
          };
        };
      };
    };

    # GVFS for Nautilus network share browsing (SMB, etc.)
    services.gvfs.enable = true;

    boot.loader.systemd-boot.enable = true;
    boot.loader.efi.canTouchEfiVariables = true;

    networking.hostId = "98a5ee60";

    nixpkgs.config.allowUnfree = true;

    # TODO: Revisit the host + user stateVersions (system 26.05, HM 24.11 in
    # modules/users/giodamelio.nix) once the den migration has soaked — bump
    # deliberately after confirming no stateful service/data migrations are
    # needed.
    system.stateVersion = "26.05";
  };
}
