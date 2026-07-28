# Remote Second Session — First-Principles Investigation

Goal: a Wayland session on a server host (cadmium) that is **separate from the local
desktop session**, may run **concurrently** with it under the **same user**, and that a
laptop **attaches to and detaches from** over the network.

This supersedes the reasoning in `docs/remote-wayland-niri-session.md`, which solved a
different problem: replacing the laptop's local session with a forwarded one that dies
with the SSH connection.

## 1. Decomposing "a session"

"Session" is four independent layers that people conflate. Almost every problem below
comes from one layer being per-seat, per-session, or per-user when you assumed otherwise.

| Layer | Thing | Scope | Can you have two? |
|---|---|---|---|
| 0 | DRM master / seat | per **seat**, per **active** session | No — only the foreground session on seat0 owns the GPU outputs |
| 1 | Compositor process | per process | Yes, freely |
| 2 | logind session | per login | Yes — `loginctl list-sessions` shows several |
| 3 | `systemd --user` + D-Bus + `XDG_RUNTIME_DIR` | per **UID** | **No.** This is the wall. |
| 4 | Transport | per connection | Yes |

Layers 0–2 are easy. Layer 3 is where "two sessions, one user" actually fails, and it
fails quietly rather than loudly.

## 2. Layer 0 — you cannot have two compositors on the pixels

logind revokes DRM and input devices from a session the moment it becomes inactive; VT
switching is precisely that handover. Two DRM-backend compositors on seat0 cannot run
concurrently — the second gets `EACCES` or steals the display.

So the second session must avoid DRM entirely. The real options:

- **Headless backend** — no DRM, no libinput. wlroots: `WLR_BACKENDS=headless`,
  `WLR_LIBINPUT_NO_DEVICES=1`. Renders via the GPU's *render node* (`/dev/dri/renderD128`,
  needs `video`/`render` group), which requires no DRM master. This is the correct answer.
- **Nested / winit backend** — the second compositor is a Wayland client of the first.
  Works, but it is inside the desktop session: it dies with it, is visible on it, and
  inherits its lifetime. Not a separate session in any meaningful sense.
- **A second seat** — `loginctl attach seat1 <sysfs-path>` with a spare GPU. Genuinely
  independent, but needs real hardware. `vkms` (virtual KMS) can fake the DRM device, but
  you then need a multi-GPU render/scanout split. Interesting, not recommended.

## 3. Layer 4 — persistence forces a pixel transport

This is the finding that kills the previous approach.

**waypipe puts the compositor on the client.** `waypipe server` creates a fake compositor
socket on the remote host and forwards clients to `waypipe client`, which connects to the
laptop's real compositor. The remote apps therefore depend on the laptop's compositor
being reachable. When the link drops, `waypipe server` exits and every client attached to
its fake display dies.

Worse, **waypipe 0.11.0 has no reconnection**. The C implementation had a `recon`
subcommand; the Rust rewrite dropped it in 0.10.0. I confirmed this against the manpage of
the exact package nixpkgs would give you:

```
$ zcat .../waypipe-0.11.0/share/man/man1/waypipe.1.gz | grep -c recon
0
```

The documented modes are `ssh`, `client`, `server`, `bench`. Nothing else.

Therefore: **if you want to detach and reattach, the compositor must live on the server,
and the transport must be pixels.** waypipe is structurally incapable of this, no matter
how it is wrapped. It remains excellent for its actual use case — running one remote app
inside your laptop's local niri — and is worth keeping for that.

Pixel transports, in rough order of fit:

| Transport | Attach/detach | Audio | Encoding | Notes |
|---|---|---|---|---|
| **wayvnc** 0.10.0 | yes | no | CPU, some hw | Needs `wlr-screencopy` or `ext-image-copy-capture-v1` + virtual pointer/keyboard. You already have an aspect for it. |
| **Sunshine/Moonlight** | yes | yes | hw H.264/HEVC/AV1 | Best latency over WAN, real audio. Needs a virtual display. |
| **RDP** (gnome-remote-desktop) | yes | yes | hw | GNOME-only, but see §6 — it is the reference architecture for this exact problem. |
| **waypipe** | **no** | no | n/a (protocol forwarding) | Sharpest text, lowest bandwidth for non-video. No persistence. |

## 4. Layer 1 — which compositor, given niri 26.04

niri **cannot** run standalone headless today. Its headless backend is a test harness with
no output at all, and virtual outputs are unmerged: [discussion
#3101](https://github.com/niri-wm/niri/discussions/3101) has an `niri msg action
create-virtual-output` prototype and an `output { virtual }` config keyword, but YaLTeR
had not merged it as of June 2026, and flagged a real design problem — *virtual outputs
only render while a screencopy client is attached*, so nothing drives frame callbacks
when you detach. In [discussion #714](https://github.com/niri-wm/niri/discussions/714) the
maintainer's position is simply "not at the moment"; a community fork
(QaidVoid) implements it and reportedly works with both Moonlight and wayvnc.

The 26.04 release notes confirm this: blur, `ext-background-effect`,
`ext-foreign-toplevel-list`, DMA-BUF for nested niri — no virtual outputs.

So, three ways to get a headless server-side compositor:

1. **sway headless** — `WLR_BACKENDS=headless WLR_LIBINPUT_NO_DEVICES=1 sway`, then
   `swaymsg create_output` and `output HEADLESS-1 mode 1920x1200@60Hz`. Well-trodden with
   wayvnc, and your existing `wayvnc` aspect already binds to `sway-session.target`, so it
   drops straight in. The remote session is sway, not niri.
2. **niri nested inside headless sway** — sway provides the headless output, niri runs in
   winit mode fullscreen inside it, wayvnc captures sway. You keep niri as the actual WM at
   the cost of a compositor layer and some input/scaling seams. 26.04's nested DMA-BUF
   support helps here.
3. **Wait for niri virtual outputs**, or run the fork. Note the detach-stops-rendering
   caveat before relying on it.

One protocol caveat worth testing rather than trusting: niri implements `wlr-screencopy`
v3 and virtual pointer/keyboard, but Smithay-based virtual input implementations have a
reputation for gaps (the `wl-uinput-proxy` project exists specifically to work around
them). If you go route 2 or 3, verify input injection early — it is the most likely thing
to be subtly broken.

## 5. Layer 3 — the wall: everything important is per-UID

`systemd --user` is **per user, not per session**, by explicit design: user services own
resources in `$HOME`, which is shared across sessions. One `user@1000.service`, one
`XDG_RUNTIME_DIR=/run/user/1000`, and — contrary to the older "session bus" docs — one
D-Bus session bus at `$XDG_RUNTIME_DIR/bus`, socket-activated by that same user manager.

Consequences, concretely.

### 5.1 The environment-clobbering bug

Session startup conventionally does `systemctl --user import-environment` (or
`dbus-update-activation-environment`) to publish `WAYLAND_DISPLAY`, `DISPLAY`,
`XDG_CURRENT_DESKTOP` into the user manager. There is exactly one such environment block.
**The second session to start overwrites the first's.** Every user service activated
*after* that point — portals, notification daemons, anything socket- or D-Bus-activated —
connects to the wrong compositor. Already-running services keep working, which is why this
presents as "it worked yesterday" rather than a clean failure.

Your `niri.service` is a plain instance of this pattern:

```nix
systemd.user.services.niri = {
  bindsTo = ["graphical-session.target"];
  before = ["graphical-session.target" ...];
};
```

`graphical-session.target` is a per-user singleton. Two sessions cannot both "be" it.
systemd deliberately forbids starting it directly for this reason, which is why
compositor-specific targets (`sway-session.target`, `niri.service`) exist — but those only
solve *naming*, not the underlying single-manager problem.

### 5.2 The singleton inventory

Everything here is one-per-UID. In a two-session world, exactly one session wins each:

**D-Bus well-known names** (first claimant owns it, others get nothing):
- `org.freedesktop.Notifications` — remote session's notifications pop up on the desktop
- `org.freedesktop.impl.portal.desktop.*` — screenshots/screencasts capture the wrong screen
- `org.kde.StatusNotifierWatcher` — tray icons land in one bar
- `org.freedesktop.secrets` (gnome-keyring) — unlock prompt appears on the wrong screen
- MPRIS, idle-monitor, `org.freedesktop.ScreenSaver` inhibitors

**`$XDG_RUNTIME_DIR` collisions:** Wayland sockets are fine (`wayland-1`, `wayland-2`
auto-increment), but `pipewire-0`, `pulse/native`, `bus`, `wayvncctl`, `gnupg/S.gpg-agent`
and app single-instance sockets are fixed names.

**PipeWire/WirePlumber:** one instance. Audio from the remote session comes out of the
desktop's speakers — a genuine problem, not cosmetic, and VNC won't fix it since it carries
no audio.

**Portals:** `xdg-desktop-portal` reads `XDG_CURRENT_DESKTOP` from the manager environment
at activation. Your niri aspect already pins the backend (`xdg.portal.config.niri`) and
already carries an ordering workaround for the WAYLAND_DISPLAY race — a second compositor
makes that race permanent rather than a startup transient.

**Xwayland:** each compositor wants its own `xwayland-satellite`; `:0` vs `:1` is fine, but
`DISPLAY` in the manager env is singular, so X apps launched from user services land in
whichever session set it last.

**Clipboard, idle, lock:** per-compositor by nature; the singleton daemons (cliphist,
swayidle) bind to one.

### 5.3 Programs that get upset

The "same user, two sessions" failure mode users actually notice is single-instance apps
that hold a lock or IPC socket under `$HOME` or `$XDG_RUNTIME_DIR`. Launching one in the
remote session finds the existing instance and **raises the window on the desktop's
screen** — you click, and nothing appears on your laptop.

Affected in your config: Firefox (`.parentlock` in the profile), qutebrowser (IPC socket
keyed on `$XDG_RUNTIME_DIR`), Chromium/camoufox, Slack, Obsidian, VS Code, Steam, Emacs
`server-socket`, `nvim --listen`, keepassxc, syncthing's GUI. Firefox can be forced with a
second profile plus `MOZ_ENABLE_WAYLAND` and its own `$XDG_RUNTIME_DIR`; most of the
others key on `$XDG_RUNTIME_DIR` and therefore fix themselves under §6's approaches.

## 6. Three ways past the wall

### A. Separate UID — `giodamelio-remote`

The only approach where every singleton is *naturally* disjoint: own `user@1001.service`,
own `/run/user/1001`, own bus, own PipeWire, own portals, own app locks. No coordination
needed, nothing to remember.

Costs: separate `$HOME`, so separate keyring, browser profile, shell history, agevault
secrets, ssh/gpg agents. Shared work directories need a group and `setgid`/ACLs. You'd
generate both users' home-manager configs from the same aspects, so config duplication is
free; only *state* duplicates — and for browsers, duplicate state is what you want anyway.

This is what GNOME concluded too. `gnome-remote-desktop`'s headless remote-login mode
doesn't reuse the local session: a **system** daemon takes the RDP connection, GDM creates
a genuinely separate login session, and a per-session handover daemon claims the client
over D-Bus. PipeWire for pixels, libei for input. The architecture exists because sharing a
user session was not viable.

### B. Same UID, namespaced session

Run the remote session in a mount namespace with its own `XDG_RUNTIME_DIR` (e.g.
`/run/user/1000/remote` on a private tmpfs) and a private bus via `dbus-run-session`.
Portals, PipeWire, notifications and app locks all become per-session because the paths
diverge.

The catch: you cannot run a second `systemd --user` for the same UID without a PID
namespace. So either accept a full `systemd-nspawn` container (heavy; GPU/render node and
`$HOME` bound in), or run the remote session **without systemd integration at all** — a
plain script starting compositor and helpers directly. That's quite workable, but it
discards socket activation, so your existing wayvnc aspect's design (socket-activated,
idle-shutdown via a path unit) would need rewriting.

### C. Same UID, discipline only

Two compositors, shared everything. Never call `import-environment`; launch everything with
an explicit `WAYLAND_DISPLAY` via `systemd-run --user --setenv=`. Cheapest and by far the
most fragile — you will hit §5.3 constantly, and the failures are confusing rather than
loud. Fine for an experiment; bad as a durable setup.

### Recommendation

**A**, with **sway headless + wayvnc** as the first working version, since your wayvnc
aspect already targets `sway-session.target` and the second UID makes it a near-drop-in.
Add `loginctl enable-linger` for that user so the session survives having no login
session — without it, the user manager is torn down when you disconnect, which defeats the
entire point. Reach for Sunshine when you want audio and WAN-grade latency, and keep
waypipe for single remote apps into your local niri.

If keeping niri specifically matters more than simplicity, do A + nested-niri-in-headless-sway
(§4 route 2) and budget time for input-injection debugging.

## 6b. Revision: dropping the concurrency requirement

If the two sessions never run at the same time, the analysis changes — but only halfway.
**Concurrency and persistence are orthogonal problems**, and only the first one goes away.

**What dropping concurrency fixes.** All of §5. With the desktop session fully stopped
(`systemctl --user stop niri`, not merely locked), nothing contends for the D-Bus names,
`XDG_RUNTIME_DIR` paths, PipeWire, portals, or app locks. The environment-clobbering bug in
§5.1 becomes harmless, because the session doing the clobbering is the only one left. This
is just "log out here, log in there," and it is genuinely clean. Layer 0 was never a
problem for waypipe anyway — a waypipe-hosted niri is a Wayland client and never touches
DRM. §6's whole second-UID apparatus becomes unnecessary.

**What it does not fix.** Wayland clients cannot survive losing their `wl_display`
connection; the protocol has no reconnect. So with any protocol-forwarding transport, app
lifetime is welded to connection lifetime — close the lid, lose wifi, and the session dies.
This is true whether or not a second session exists. Persistence was the *only* thing
pixel transports were buying, so the real question is just: **do you need to survive a
disconnect?**

If no — start fresh each time, let tmux/zellij and browser session-restore carry the state
— then waypipe as-is is correct and there is nothing more to design.

If yes, there are three non-pixel routes.

### waypipe-c — reconnection is still in the tarball

The removal was a build-flag decision, not a deletion. waypipe 0.11.0's source still ships
the entire C implementation and its reconnection machinery:

```
$ ls $(nix build --print-out-paths nixpkgs#waypipe.src)
... src/  waypipe-c/  meson_options.txt ...

$ grep build_c meson_options.txt
option('build_c', description: 'Build old version of waypipe (waypipe-c)',
       type: 'boolean', value: false)

$ grep -n "reconnect" waypipe-c/client.c
234: static int run_single_client_reconnector(
319: /* To support reconnection attempts, this mode creates a child
461: bool reconnectable = conn_id->header & CONN_RECONNECTABLE_BIT;
```

The Rust manpage is explicit that this is gone from the current binary — `--control C`,
`--hwvideo` and `--allow-tiled` are listed under *"Options present in older versions of
Waypipe that were removed."* nixpkgs builds only the Rust binary (`bin/` contains just
`waypipe`), so `waypipe-c` needs a package:

```nix
waypipe-c = pkgs.waypipe.overrideAttrs (old: {
  mesonFlags = (old.mesonFlags or []) ++ ["-Dbuild_c=true"];
});
```

Usage, from `waypipe-c/waypipe.c`'s own help text:

```
recon C T    Reconnect a 'waypipe server' instance. Writes the new Unix
               socket path T to the control pipe C.
--control C  server,ssh: set control pipe to reconnect server
```

So: start the server side with `--control /path/to/pipe`; when the link dies, establish a
new forwarded socket and run `waypipe-c recon /path/to/pipe /new/socket`. Both waypipe
instances stay alive the whole time — only the transport between them is replaced, which is
why the Wayland connections survive. This keeps dmabuf and video encoding, unlike wprs.

Costs: the C branch is frozen legacy, and the Rust rewrite exists precisely because it
greatly improved network performance. You would be trading throughput for persistence, and
maintaining an out-of-tree nixpkgs override.

### wprs — purpose-built for this

[wprs](https://github.com/wayland-transpositor/wprs) is the xpra model for Wayland:
`wprsd` is a Smithay-based compositor on the remote host that owns the client connections
and serializes surface state; `wprsc` is a local Wayland client that recreates those
surfaces as native windows in your niri. Because the compositor is server-side and holds
the connections, `wprs <host> detach` / `wprs <host> attach` genuinely work, and wprsc can
restart freely. It is in nixpkgs (`0-unstable-2025-09-05`).

The caveats are significant and disqualifying for some uses:
- **No dmabuf, no GPU acceleration, no hardware rendering.** Everything is CPU-side.
- **Only core and XDG shell protocols.** No layer-shell — so waybar/noctalia won't run, and
  a nested niri almost certainly won't work as a wprsd client. This is the *rootless* model:
  individual app windows in your local niri, not a remote session with its own WM.
- Protocol explicitly not stable; both ends must be the same build (fine — same nixpkgs).
- No touch events; drag-and-drop is flaky; WebAuthn/security keys don't work in browsers.
- XWayland only via a separate `xwayland-xdg-shell` binary.

### TCP over the existing wg mesh — cheap partial credit

Not real persistence, but: replace SSH with a plain TCP bridge (socat) between the two
waypipe sockets, carried over your existing WireGuard mesh. WireGuard roams across IP
changes, and a TCP connection with no traffic survives on the order of minutes of outage
before timing out. Brief wifi blips and short suspends survive; a real detach does not.
Roughly an hour of work, no packaging, and it composes with the waypipe-c route.

### Verified gotcha: `niri --session` can never work under waypipe

niri 26.04 deliberately destroys the environment waypipe sets up. From `src/main.rs:73`:

```rust
if cli.session {
    // If we're starting as a session, assume that the intention is to start on a TTY unless
    // this is a WSL environment. Remove DISPLAY, WAYLAND_DISPLAY or WAYLAND_SOCKET from our
    // environment if they are set, since they will cause the winit backend to be selected
    // instead.
```

`--session` unsets `WAYLAND_DISPLAY` and forces the TTY/DRM backend, which is exactly what
you cannot use. So a waypipe-hosted niri must run **without** `--session` — which is also
what makes it safe (no `import-environment`, so no §5.1 clobbering) but means niri does not
set `XDG_CURRENT_DESKTOP=niri`/`XDG_SESSION_TYPE=wayland` and does not pull up
`graphical-session.target`. Your waybar, noctalia, portals and handy will not autostart.
Either launch them explicitly from the remote niri config with the right `WAYLAND_DISPLAY`,
or define a separate `remote-session.target` that the nested niri starts by hand.

Also new in 0.11 and relevant to you: `--xwls` runs X clients via `xwayland-satellite`
directly from waypipe, which you already have packaged.

### Revised recommendation

Keep waypipe; drop the second-UID machinery and all of §6. Then:

- **If a fresh session per connection is acceptable** — build exactly what the old work log
  described, minus the `--session` flag, plus explicit startup of the session services.
  Nothing else needed.
- **If you want detach/reattach and want to keep GPU-accelerated, full-fidelity forwarding
  of a whole niri session** — package `waypipe-c` with `-Dbuild_c=true` and wrap the
  `--control`/`recon` dance in a small script. This is the option that best matches "waypipe
  has been great."
- **wprs only if you're happy with the rootless model** (individual windows, no remote WM,
  no GPU). It is the most purpose-built and the least like what you said you enjoyed.

## 7. Prerequisites and open questions

Prerequisites, whichever path:
- `loginctl enable-linger <user>` — mandatory for persistence.
- Check `logind.conf` `KillUserProcesses` is off (NixOS default is off).
- The session user needs `video`/`render` group for the render node.
- Decide network exposure: SSH tunnel vs. the existing wg mesh. wayvnc's auth is weak
  enough that it should never be directly exposed.

Open questions to settle before building:
1. Does the remote session need **audio**? If yes, wayvnc is out as the primary transport
   and Sunshine moves to first choice.
2. Does it need to be **niri specifically**, or is sway acceptable for the remote session?
   This is the single biggest complexity fork.
3. Separate UID acceptable, or is shared `$HOME` state a hard requirement? If the latter,
   §6B and its rewrite of the wayvnc aspect become necessary.
4. Should the remote session be **always-on** (lingering service) or **on-demand**
   (socket-activated, torn down when idle, like the current wayvnc design)?
