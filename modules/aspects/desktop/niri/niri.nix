# niri — the scrollable-tiling Wayland compositor. Folded dual-class aspect:
#   - nixos half: the compositor + display manager (was nix/modules/nixos/niri.nix).
#   - homeManager half: handy + iconography + niri packages (was
#     nix/modules/home/niri.nix). Its Blueprint `imports` of sibling home modules
#     (noctalia, niri-launcher-binds, niri-launcher-desktop-entries,
#     satellite-wallpaper, niri-settings) become aspect `includes` below; those
#     are homeManager-only aspects, so they're no-ops when niri is on a host.
#
#   - external niri / handy input modules imported via the file-scope `inputs`
#     closure.
#   - `perSystem.giopkgs.niri` is a module arg from the per-system aspect.
{
  inputs,
  den,
  ...
}: {
  den.aspects.niri.includes = [
    den.aspects.noctalia
    den.aspects.niri-launcher-binds
    den.aspects.niri-launcher-desktop-entries
    den.aspects.satellite-wallpaper
    den.aspects.niri-settings
  ];

  den.aspects.niri.nixos = {
    perSystem,
    lib,
    pkgs,
    ...
  }: let
    niriPackage = perSystem.giopkgs.niri.overrideAttrs (old: {
      passthru =
        old.passthru or {}
        // {
          providedSessions = ["niri"];
        };
      postFixup =
        old.postFixup or ""
        + ''
          substituteInPlace $out/share/systemd/user/niri.service \
            --replace-fail "ExecStart=niri" "ExecStart=$out/bin/niri"
        '';
    });
  in {
    imports = [inputs.niri.nixosModules.niri];

    programs.niri.enable = true;
    programs.niri.package = niriPackage;

    environment.systemPackages = with pkgs; [
      waypipe
    ];

    # The gnome portal refuses to expose FileChooser without Mutter,
    # so route it to the GTK portal explicitly.
    xdg.portal.extraPortals = [pkgs.xdg-desktop-portal-gtk];
    xdg.portal.config.niri = {
      default = ["gtk"];
      "org.freedesktop.impl.portal.FileChooser" = ["gtk"];
    };

    # Fix portal services starting before niri-session has exported
    # WAYLAND_DISPLAY. See: https://github.com/sodiboo/niri-flake/issues/509
    systemd.user.services.xdg-desktop-portal = {
      after = ["xdg-desktop-autostart.target"];
      # Override the restricted PATH from the upstream unit so the portal
      # can find and launch desktop apps (e.g. firefox for OpenURI).
      environment.PATH = lib.mkForce "/run/wrappers/bin:/etc/profiles/per-user/%u/bin:/nix/var/nix/profiles/default/bin:/run/current-system/sw/bin";
    };
    systemd.user.services.xdg-desktop-portal-gtk = {
      after = ["xdg-desktop-autostart.target"];
    };
    systemd.user.services.xdg-desktop-portal-gnome = {
      after = ["xdg-desktop-autostart.target"];
    };
    systemd.user.services.niri-flake-polkit = {
      after = ["xdg-desktop-autostart.target"];
    };

    services.displayManager.ly.enable = true;

    # Workaround for NixOS/nixpkgs#427414: ly's shell session pipes
    # stdout/stderr to systemd-cat, making command output invisible.
    # Disable journal redirect so shell logins behave normally.
    services.displayManager.logToJournal = false;

    # Register niri systemd user units in /etc/systemd/user/ so Ly can
    # find them. Setting PATH = null prevents NixOS from injecting a
    # restricted PATH that would break spawned programs — niri inherits
    # the user's full environment via niri-session's import-environment.
    systemd.user.services.niri = {
      description = "A scrollable-tiling Wayland compositor";
      bindsTo = ["graphical-session.target"];
      before = ["graphical-session.target" "xdg-desktop-autostart.target"];
      wants = ["graphical-session-pre.target" "xdg-desktop-autostart.target"];
      after = ["graphical-session-pre.target"];
      environment.PATH = lib.mkForce null;
      serviceConfig = {
        Slice = "session.slice";
        Type = "notify";
        ExecStart = "${niriPackage}/bin/niri --session";
      };
    };

    systemd.user.targets.niri-shutdown = {
      description = "Shutdown running niri session";
      conflicts = ["graphical-session.target" "graphical-session-pre.target"];
      after = ["graphical-session.target" "graphical-session-pre.target"];
      unitConfig = {
        DefaultDependencies = false;
        StopWhenUnneeded = true;
      };
    };

    # Ensure systemd user services have the full NixOS PATH available
    # (same approach as the Hyprland NixOS module)
    systemd.user.extraConfig = ''
      DefaultEnvironment="PATH=/run/wrappers/bin:/etc/profiles/per-user/%u/bin:/nix/var/nix/profiles/default/bin:/run/current-system/sw/bin"
    '';

    # Noctalia prerequisites
    services.upower.enable = true;
  };

  # Home-Manager half (was nix/modules/home/niri.nix). The sibling home modules
  # it used to import are pulled in via den.aspects.niri.includes above; the
  # external handy module is imported here at file scope.
  den.aspects.niri.homeManager = {
    perSystem,
    pkgs,
    ...
  }: {
    imports = [
      inputs.handy.homeManagerModules.default
    ];

    # Speech to text
    services.handy.enable = true;

    gtk.iconTheme = {
      name = "Adwaita";
      package = pkgs.adwaita-icon-theme;
    };

    home.pointerCursor = {
      name = "Adwaita";
      package = pkgs.adwaita-icon-theme;
      size = 24;
      gtk.enable = true;
    };

    home.packages =
      [perSystem.giopkgs.niri]
      ++ (with pkgs; [
        nautilus
        xwayland-satellite
        libnotify
        wl-clipboard
        swayidle
        brightnessctl
        slurp # Allow selecting screen area (returns geometry)
        grim # Takes screenshots
        satty # Screenshot annotation
        xdg-user-dirs # Easily get XDG dirs inside scripts
        wtype # For handy to type text
      ]);
  };
}
