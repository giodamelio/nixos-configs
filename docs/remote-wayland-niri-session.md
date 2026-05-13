Remote Cadmium Niri Session — Work Log

Goal

Run niri on cadmium (desktop) as a remote session accessible from cesium
(Chromebook), using waypipe over SSH. The session should:
- Launch from Ly's login screen on cesium, replacing the local niri session
entirely
- Be transparent — no visible wrapper compositor chrome
- Forward all input/output to cadmium's niri with a single-display layout

---
Part 1: Niri Config Architecture

How niri-flake's HM Module Gets Imported

The niri flake exports two things that seem separate but are linked:
- nixosModules.niri — the NixOS-level module
- homeModules.config — the Home Manager module

You never explicitly imported homeModules.config anywhere. It gets injected
automatically by nixosModules.niri, which hooks into Home Manager's
sharedModules or extraSpecialArgs when it detects HM is present. This is why
programs.niri options are available in HM configs even though you only have
imports = [inputs.niri.nixosModules.niri] on the NixOS side.

Generating Multiple Niri Configs

The goal: cadmium needs two niri configs:
1. ~/.config/niri/config.kdl — the normal 3-monitor layout (existing)
2. ~/.config/niri/single-display.kdl — same shared settings but no explicit
output layout or workspace-to-output assignments, for use over waypipe from
cesium

How niri-flake makes this possible:

The flake cleanly separates two layers:
- lib.internal.settings-module — a pure module (no HM/NixOS deps) that only
declares programs.niri.settings.* options and computes
programs.niri.finalConfig from them. No filesystem side effects. The niri
flake itself uses this module in its own test suite via lib.evalModules.
- homeModules.config — wraps the settings module and writes config.kdl to
~/.config/niri/config.kdl (hardcoded path).

Key exported symbols:
inputs.niri.lib.internal.settings-module          # pure settings module
inputs.niri.lib.internal.validated-config-for     # pkgs → package →
configStr → storePath
                                                # runs `niri validate` and
returns store path

Initial (Ugly) Approach — Rejected

The first attempt used lib.evalModules with an attrset merge:

singleDisplayEval = lib.evalModules {
modules = [
  inputs.niri.lib.internal.settings-module
  {
    config.programs.niri.settings = config.programs.niri.settings // {
      outputs = {};
      workspaces = {};
    };
  }
];
};

This worked but was ugly — it read the fully-evaluated HM settings attrset
and used // to override top-level keys. The source location tracking is lost
(warnings say <unknown-file> instead of pointing at the actual nix file).
Also caused evaluation warnings about animations.shaders.* being obsolete
(coming from the noctalia module via the double-evaluation).

Final (Clean) Approach — Module Composition

The key insight: any module that only sets config.programs.niri.settings.*
values is compatible with both the HM module system (which declares those
options via homeModules.config) and a standalone lib.evalModules { modules =
[settings-module ...] } call. The same module file can be used in both
contexts.

File structure created:

nix/modules/home/
niri.nix              # HM infrastructure: packages, services, cursor,
noctalia, satellite-wallpaper
niri-settings.nix     # ONLY programs.niri.settings.* — shared between HM
and standalone evalModules

nix/hosts/cadmium/users/giodamelio/
niri.nix              # imports flake.homeModules.niri +
./niri/three-monitor.nix,
                      # generates single-display.kdl via lib.evalModules
niri/
  three-monitor.nix   # outputs + workspaces for the 3-monitor layout (HM
module)
  single-display.nix  # layout.gaps override etc. for single-display
variant

niri.nix (cadmium HM module):
{ lib, pkgs, config, inputs, flake, ... }:
let
singleDisplayConfig =
  inputs.niri.lib.internal.validated-config-for
  pkgs
  config.programs.niri.package
  (lib.evalModules {
    specialArgs = { inherit pkgs; };
    modules = [
      inputs.niri.lib.internal.settings-module
      flake.homeModules.niri-settings   # same file the HM module uses
      ./niri/single-display.nix
    ];
  }).config.programs.niri.finalConfig;
in {
imports = [
  flake.homeModules.niri
  ./niri/three-monitor.nix
];
xdg.configFile."niri/single-display.kdl".source = singleDisplayConfig;
}

Important: niri-settings.nix uses pkgs.procps in the keybindings, so pkgs
must be passed via specialArgs to lib.evalModules. lib is automatically
available in evalModules without needing to be in specialArgs.

Conflict with lib.mkDefault: single-display.nix sets layout.gaps = 100
(temporarily, for testing), which conflicts with niri-settings.nix setting
layout.gaps = 0. Fixed by marking the base value as lib.mkDefault 0 in
niri-settings.nix, so variant modules can override it.

package argument: validated-config-for must be called with
config.programs.niri.package, which is the custom perSystem.giopkgs.niri
(with providedSessions and systemd fixup applied). Do not use pkgs.niri here.

---
File Restructuring (Both Hosts)

Blueprint supports two forms for HM user configs:
- nix/hosts/<host>/users/<user>.nix (old form)
- nix/hosts/<host>/users/<user>/home-configuration.nix (directory form)

Changes made:

┌─────────────────────────────┬──────────────────────────────────────────┐
│             Old             │                   New                    │
├─────────────────────────────┼──────────────────────────────────────────┤
│ nix/hosts/cadmium/users/gio │ nix/hosts/cadmium/users/giodamelio/home- │
│ damelio.nix                 │ configuration.nix                        │
├─────────────────────────────┼──────────────────────────────────────────┤
│ nix/hosts/cadmium/hm-niri.n │ nix/hosts/cadmium/users/giodamelio/niri. │
│ ix                          │ nix                                      │
├─────────────────────────────┼──────────────────────────────────────────┤
│ nix/hosts/cesium/users/giod │ nix/hosts/cesium/users/giodamelio/home-c │
│ amelio.nix                  │ onfiguration.nix                         │
├─────────────────────────────┼──────────────────────────────────────────┤
│ nix/hosts/cesium/hm-niri.ni │ nix/hosts/cesium/users/giodamelio/niri.n │
│ x                           │ ix                                       │
└─────────────────────────────┴──────────────────────────────────────────┘

Also consolidated flake.homeModules.noctalia and
flake.homeModules.satellite-wallpaper imports into nix/modules/home/niri.nix
(they were duplicated in every host's old hm-niri.nix).

Cesium's niri.nix is currently a minimal stub — just imports the shared
module — ready for future cesium-specific display configuration:
{ flake, ... }: {
imports = [flake.homeModules.niri];
}

---
Part 2: Remote Waypipe Session

How Waypipe Actually Works

Important — the socket model is counterintuitive:

- waypipe client --socket PATH — the client CREATES (binds/listens on) the
socket
- waypipe server --socket PATH program — the server CONNECTS to the socket
- SSH must use -R (reverse tunnel), NOT -L

This is the opposite of the typical client-server convention. Confirmed by
the waypipe man page example and by empirical evidence (EADDRINUSE error when
SSH -L created the socket before waypipe client could bind it).

Manual connection (3-step):
# cesium — waypipe client listens
waypipe --socket /run/user/1000/waypipe-client.sock client

# cesium — SSH reverse tunnel: cadmium's socket → cesium's client socket
ssh -R /run/user/1000/waypipe-remote.sock:/run/user/1000/waypipe-client.sock
\
  giodamelio@cadmium.gio.ninja \
  "WAYLAND_DISPLAY=wayland-1 waypipe --socket
/run/user/1000/waypipe-remote.sock \
  server niri --config ~/.config/niri/single-display.kdl"

Simpler — just use waypipe ssh:
waypipe ssh giodamelio@cadmium.gio.ninja \
  niri --config "$HOME/.config/niri/single-display.kdl"

waypipe ssh handles the SSH + IPC via stdin/stdout internally. For this use
case (on-demand session, no reconnection needed) it's the right tool. The
socket approach only adds value if you need persistent reconnectable
sessions, which waypipe doesn't support anyway.

On reconnection: Neither approach supports reconnecting to an existing
session. When the connection drops, niri dies. For persistent reconnectable
sessions, wayvnc (already configured on cadmium) is the right tool.

Shell expansion gotcha: --config=~/.config/... does NOT expand ~ (tilde is
only expanded at the start of a word). Use --config "$HOME/.config/..." or
--config ~/.config/... (space-separated) instead. Niri receives the literal ~
character and fails with "No such file or directory".

The waypipe-remote.nix Service (Removed)

An earlier attempt set up a systemd socket-activated service on cadmium:
# WRONG approach — removed
systemd.user.sockets.waypipe-remote = { ... ListenStream =
"%t/waypipe-remote.sock"; };
systemd.user.services.waypipe-remote = {
environment.WAYLAND_DISPLAY = "wayland-1";
serviceConfig.ExecStart = "waypipe --socket %t/waypipe-remote.sock server
niri ...";
};

This was wrong because:
1. Socket activation assumes the service LISTENS on the socket — but waypipe
server CONNECTS, it doesn't listen
2. The SSH tunnel direction was documented as -L (wrong), should be -R
3. For the waypipe ssh approach, no persistent server-side service is needed
at all

This file has been deleted from cadmium's config.

Ly Session Entry for Cesium

File: nix/hosts/cesium/remote-wayland-cadmium.nix

Creates a Niri (Cadmium) entry in Ly's session list.
services.displayManager.sessionPackages requires packages to have
passthru.providedSessions set — pkgs.writeTextDir doesn't set this, so a
pkgs.runCommand derivation is needed.

{ pkgs, ... }: let
cadmiumNiri = pkgs.writeShellApplication {
  name = "cadmium-niri";
  runtimeInputs = [ pkgs.cage pkgs.waypipe ];  # NOTE: cage pending
replacement — see below
  text = ''
    export LIBSEAT_BACKEND=logind
    exec cage -D -- waypipe ssh giodamelio@cadmium.gio.ninja \
      niri --config "$HOME/.config/niri/single-display.kdl"
  '';
};

desktopFile = pkgs.writeText "cadmium-niri.desktop" ''
  [Desktop Entry]
  Name=Niri (Cadmium)
  Comment=Remote niri session on cadmium via waypipe
  Exec=${cadmiumNiri}/bin/cadmium-niri
  Type=Application
'';
in {
services.displayManager.sessionPackages = [
  (pkgs.runCommand "cadmium-niri-session" {
    passthru.providedSessions = [ "cadmium-niri" ];
  } "mkdir -p $out/share/wayland-sessions && cp ${desktopFile}
$out/share/wayland-sessions/cadmium-niri.desktop")
];
}

---
Part 3: Compositor Wrapper — Ongoing

waypipe is a Wayland client — it needs a compositor to connect to. The
compositor on cesium is just a dumb wrapper; all the actual desktop
interaction happens on cadmium's niri via waypipe.

cage — Does Not Work on Cesium

cage is the standard single-app kiosk compositor and is what the session
script currently uses, but it does not work reliably on cesium's Chromebook
hardware.

Symptoms:
- Without -D flag: cage starts but never enables the output, never spawns the
child process, silent failure
- With -D flag: cage fully initializes (connects to parent Wayland, lists
globals, enables output) but child app exits in ~5ms with no error

-D flag: Not a documented cage flag (official flags are -d for debug, -s for
scale). Despite being undocumented, it has a clear effect — without it cage
fails silently on this hardware. With it, cage uses the Wayland backend (runs
nested inside an existing compositor). It may force Wayland backend
regardless of WAYLAND_DISPLAY.

Things tried:
- WLR_RENDERER=pixman — forces software rendering, avoids GPU issues
- WLR_NO_HARDWARE_CURSORS=1 — forces software cursors
- LIBSEAT_BACKEND=logind — seat management
- Various combinations of the above
- Launching from within niri session, from Ly's shell session
- Different child apps (wezterm, waypipe)

None produced a working session. Cage works on some hardware but cesium's
Chromebook GPU setup appears to be incompatible.

weston with kiosk-shell — Works but Has Wrapper Window

weston --shell=kiosk-shell.so -- waypipe ssh giodamelio@cadmium.gio.ninja \
  niri --config "$HOME/.config/niri/single-display.kdl"

The remote session ran successfully. However, weston wraps the waypipe window
in a visible compositor window with chrome (title bar / decorations
visible). Not suitable for the transparent pass-through goal.

sway with minimal config — Being Tested

sway is i3-compatible but with a minimal config it is entirely transparent.
Key properties:
- Custom config file replaces the default config entirely — no default
keybindings apply unless explicitly added
- With no bindsym lines, all keyboard input passes through to waypipe →
cadmium's niri unmodified
- for_window [app_id=".*"] fullscreen enable makes waypipe fill the screen
immediately

Config file (save to ~/.config/sway/cadmium-remote):
bar {}
default_border none
exec waypipe ssh giodamelio@cadmium.gio.ninja niri --config
"$HOME/.config/niri/single-display.kdl"; swaymsg exit
for_window [app_id=".*"] fullscreen enable

The ; swaymsg exit at the end of exec causes sway to exit cleanly when
waypipe exits (i.e. when you exit niri on cadmium), returning control to Ly.

Test command:
sway --config ~/.config/sway/cadmium-remote

Status: Being tested at time of writing.

---
Current State of remote-wayland-cadmium.nix

The session script currently uses cage (pending replacement with sway if sway
test succeeds). To update to sway:

cadmiumNiri = pkgs.writeShellApplication {
name = "cadmium-niri";
runtimeInputs = [ pkgs.sway pkgs.waypipe ];
text = ''
  exec sway --config ${pkgs.writeText "cadmium-remote-sway-config" ''
    bar {}
    default_border none
    exec waypipe ssh giodamelio@cadmium.gio.ninja niri --config
"$HOME/.config/niri/single-display.kdl"; swaymsg exit
    for_window [app_id=".*"] fullscreen enable
  ''}
'';
};

---
Next Steps

1. Confirm sway minimal config works on cesium (test with sway --config
~/.config/sway/cadmium-remote)
2. If sway works: update remote-wayland-cadmium.nix to use sway instead of
cage
3. Remove the temporary layout.gaps = 100 test value from
nix/hosts/cadmium/users/giodamelio/niri/single-display.nix
4. Deploy updated cesium config and test full flow: log into Ly → select
"Niri (Cadmium)" → cadmium desktop appears
5. Future: add cesium-specific niri display configuration in
nix/hosts/cesium/users/giodamelio/niri.nix when needed
