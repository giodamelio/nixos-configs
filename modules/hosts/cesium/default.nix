# cesium — Chromebook travel laptop (NixOS). First den host with a Home-Manager
# user. Migrated from nix/hosts/cesium/. Hardware lives in ./hardware.nix (also
# a cesium.nixos contribution).
#
# Wiring (the simple rule): the host includes the NixOS feature aspects; the
# giodamelio user includes the Home-Manager feature aspects. The two folded
# dual-class aspects (niri, kde-connect) go on the user — den applies their
# `.nixos` half to the host automatically ("users shape their host").
#
# Dropped vs Blueprint: nix/hosts/cesium/remote-wayland-cadmium.nix (the
# waypipe-to-cadmium second-niri session) is intentionally not ported.
{den, ...}: let
  homelab = builtins.fromTOML (builtins.readFile ../../../homelab.toml);
in {
  # Declare the host (platform from the attr path) with its user and machine
  # role. The aspects named `cesium` and `giodamelio` attach by convention.
  den.hosts.x86_64-linux.cesium = {
    role = "desktop";
    users.giodamelio = {};
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

    # TODO: Revisit the host + user stateVersions (system 26.05, HM 24.11 below)
    # once the den migration has soaked — bump deliberately after confirming no
    # stateful service/data migrations are needed.
    system.stateVersion = "26.05";
  };

  # ---- User: Home-Manager feature aspects + the folded dual-class aspects ----
  den.aspects.giodamelio = {
    includes = [
      # User account at OS + Home level. nix-activate/shpool/zmx come from
      # den.default, so they are not listed here.
      den.batteries.define-user
      den.batteries.primary-user # wheel + networkmanager
      (den.batteries.user-shell "zsh")

      # Home-Manager features.
      den.aspects.lil-scripts
      den.aspects.modern-coreutils-replacements
      den.aspects.git
      den.aspects.neovim
      den.aspects.zellij
      den.aspects.starship
      den.aspects.zsh
      den.aspects.nushell
      den.aspects.nix-index
      den.aspects.atuind
      den.aspects.claude-code
      den.aspects.jj
      den.aspects.wezterm
      den.aspects.zed-editor

      # Folded dual-class: HM half here, NixOS half forwarded to the host.
      den.aspects.niri
      den.aspects.kde-connect
    ];

    # Account details beyond what define-user/primary-user/user-shell provide.
    # Uses den's `user` class (forwarded to users.users.giodamelio by the
    # os-user battery), so the aspect never names users.users.<name> directly.
    user = {
      extraGroups = ["audio"]; # merges with wheel+networkmanager from primary-user
      openssh.authorizedKeys.keys = homelab.ssh_keys;
    };

    homeManager = {
      # TODO: HM stateVersion is still 24.11 (carried over from Blueprint).
      # Update later, deliberately, once the den-migrated cesium has soaked.
      home.stateVersion = "24.11";

      programs.home-manager.enable = true;

      # Configure Claude Code
      programs.gio-claude-code = {
        enable = true;
        installPackage = true;
      };

      # Configure nix-activate for NixOS
      gio.nix-activate-config.activation = {system = "nixos";};
    };
  };
}
