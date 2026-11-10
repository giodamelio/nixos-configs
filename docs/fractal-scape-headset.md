# Fractal Scape headset: smart mic and firmware notes

The Fractal Scape is a 2.4 GHz wireless gaming headset with a USB dongle
(`36bc:0001`). Folding the boom up mutes the mic in the headset itself, and a
button on the headset also mutes it. This page covers two things: the deployed
PipeWire "Smart Mic" that switches to the webcam when the boom is up, and the
reverse-engineering of the dongle firmware that grew out of understanding how
the mute state is exposed.

The firmware work is exploratory. The Smart Mic solves the real problem on its
own and is the part that ships.

## Read the mute and boom state

The headset never reports boom or mute changes on its own. You have to poll the
dongle over its vendor HID channel. This was verified four ways: silent packet
captures, the vendor configurer's own 1.5 s polling, the configurer's
JavaScript having no subscribe command, and a full disassembly of the dongle
firmware (see below).

Poll by writing the 3-byte report `02 f1 21` to the dongle's hidraw node, then
reading replies until one starts `02 f1 21`. Other reports share the node (for
example the vendor configurer's `02 11 21` replies), so match on the prefix.

In the 64-byte reply, counting from the report ID:

- Byte 5: mic muted. `01` muted, `00` live. Set by both the boom and the button.
- Byte 14: boom position (a Hall sensor). `01` up, `00` down.
- Byte 15: battery percentage.
- Byte 39: a copy of byte 5.

The configurer's own code labels byte 5 `isMuted = (b == 0)`, the opposite of
what hardware testing showed. Trust the test: `01` is muted.

Find the hidraw node by vendor ID rather than a fixed path, which survives
replugs:

```
grep -l 36BC /sys/class/hidraw/*/device/uevent
```

## Grant access to the dongle

Both the hidraw node and the USB node default to `root 0600`. The
`cadmium-fractal-headset` aspect
(`modules/hosts/cadmium/fractal-headset/default.nix`) creates a `fractal` group,
adds `giodamelio` to it, and ships a udev rule matching vendor `36bc` only (the
dongle re-enumerates with a different product ID while flashing, so matching the
product ID would drop access mid-flash):

```
KERNEL=="hidraw*", ATTRS{idVendor}=="36bc", MODE="0660", GROUP="fractal"
SUBSYSTEM=="usb", ATTRS{idVendor}=="36bc", MODE="0660", GROUP="fractal"
```

This access is what lets Chrome's WebHID reach the dongle for the vendor
configurer at <https://adjust.fractal-design.com/>, and what lets the Smart Mic
service poll it.

Group membership only applies to new login sessions. A lingering `systemd
--user` manager (an open ssh or tty session) keeps old groups across a
re-login, so a clean switch needs `loginctl terminate-user` or a reboot. A
freshly deployed udev rule only applies to devices that appear afterwards; run
`sudo udevadm trigger --action=change` on the node or replug the dongle.

## Smart Mic: fall back to the webcam when the boom is up

The goal was one always-present input source that carries the headset mic when
the boom is down and the webcam when it is up, while still respecting a
computer-side mute.

PipeWire cannot do this on availability alone. The headset mic stays a present,
running device when the boom is up; it just outputs digital silence. Audio-level
detection also fails, because the dongle's noise gate emits exact zeros during
speech pauses, so "boom up" and "quiet but live" look identical. The boom state
is only knowable over HID.

The design, all in the `cadmium-fractal-headset` aspect:

- A `libpipewire-module-loopback` named Smart Mic. Its capture side
  (`smart-mic-capture`) reads one real mic at a time and is marked passive, so
  it does not hold a mic open while nothing records. Its playback side
  (`smart-mic`) is an `Audio/Source` with `priority.session` above any real
  device, so WirePlumber picks it as the default source. The software
  mute and volume live on this node, after the source selection, so a
  computer-side mute holds whichever mic is feeding it.
- A small Go program (`smart-mic/`) built with `buildGoModule`
  (`vendorHash = null`, no dependencies). It watches `pw-dump --monitor` for
  events and does nothing while Smart Mic is idle. When something records from
  Smart Mic it polls the dongle's HID every 100 ms and retargets the capture
  stream with `pw-metadata <capture id> target.object <node>`. Boom down selects
  the headset; boom up selects the webcam; a button mute with the boom down
  stays on the headset (that silence is intended). If the dongle is absent or
  HID fails it falls back to the webcam. It finds the hidraw node by vendor ID
  and logs only on change, never per poll.
- A `systemd.user.services.smart-mic` unit, ordered after pipewire and
  wireplumber, restarts always.

Measured cost: zero CPU while idle (nothing records), about 0.3% of one core
while polling during a call, plus roughly 100 ms per boom switch for
`pw-metadata` and the relink. The poll rate is the `-poll` flag.

After deploying, PipeWire does not reload drop-ins on its own; restart it with
`systemctl --user restart pipewire pipewire-pulse wireplumber` (this drops audio
briefly and some apps need restarting). WirePlumber lists the loopback under
Filters, not Sources, but apps still see Smart Mic as an ordinary input.

## Dongle internals

The rest of this page records what the dongle is and how it works, from
reverse-engineering its firmware. None of it is needed to run the Smart Mic. It
exists so a later firmware-patch experiment does not start from scratch. The
scratch artifacts (decrypted firmware, scripts, disassembly notes, FCC photos,
the rebuild toolchain) live in `tmp/fractal-re/`, which jj ignores because they
contain device secrets.

### Hardware

The dongle and headset both use an **Airoha AB1565** (ARM Cortex-M4F plus a
separate audio DSP) running Airoha reference designs (`dongle_ref_design`,
`headset_ref_design`), customized by Fractal mostly in branding. The dongle's
FCC ID is `2BDPAFDSDNGLE1`; the FCC filing's internal photos show a snap-fit
clamshell case (no glue or weld), a leadless QFN SoC, and roughly 18 exposed
test points (TP1–TP18) around the chip, more than enough for SWD plus UART. The
pads are unlabeled by function, so they need probing to map.

### HID interfaces

The dongle presents USB Audio Class interfaces plus a HID interface with four
report collections:

- `0x0C` consumer control: volume, play, mute keys.
- `0xFF13` vendor page, reports `0x06` out / `0x07` in: Airoha's RACE engineering
  protocol. Unused by Fractal's configurer.
- `0x05` telephony: hook switch, phone mute, LEDs. Only active in call ("phone")
  mode.
- `0xFF00` vendor page, report `0x02`: Fractal's own protocol. This is the
  channel the configurer and the Smart Mic use.

The `0x02` protocol is `[reportID, deviceType, cmd, ...]`. Device types: `0x11`
dongle, `0xf1` headset, `0xa7` EQ. `cmd 0x21` is get-state. The dongle replies
to `02 11 21` with the headset-connected flag; the headset state comes from
`02 f1 21`. Other commands cover sidetone (`0x34`), noise cancelling (`0x36`),
factory reset (`0xf2`), EQ, and firmware update.

### Firmware is decryptable

The vendor firmware images (downloadable from the configurer) are Airoha FOTA
packages: a 32-byte SHA-256 of `file[0x100:]`, TLV records at `0x100`, then an
AES-128-CBC ciphertext from `0x1000` that decrypts to one LZMA-alone stream.

The AES key and IV are **Airoha's SDK defaults** (stored byte-reversed),
published in a decompiled copy of Airoha's own packaging tool, and Fractal never
changed them. Both images decrypt and every per-section SHA-256 digest (the
`0x14` TLV records, taken over the decompressed content) verifies. The decryptor
is `tmp/fractal-re/scripts/decrypt_fota.py`.

A toolchain to unpack, patch, and repack a valid image lives in
`tmp/fractal-re/fota-tool/`: `fotalib.py` (shared parse/AES/LZMA/verify),
`unpack.py`, `repack.py`, a `roundtrip.py` proof, a `rebuild-fota` Nix
derivation (source firmware plus a JSON byte-patch produces a verified image),
and a `README.txt`. Both images round-trip semantically: a rebuilt image
decompresses byte-for-byte to the original content and every hash recomputes
consistently, and the Nix build unpacks and self-verifies its own output.

The rebuild is **not byte-identical** to the vendor file, and cannot be. The
LZMA-alone header matches (`lc=3 lp=0 pb=2`, dict `0x4000`), but the vendor used
a 7-zip-style LZMA SDK encoder while the tool uses liblzma, so the range-coded
body differs from the first byte (liblzma compresses slightly tighter). No
matched parameters make two different encoders emit identical streams. This is
the crux of whether the device accepts a repack, covered below.

### The push question, answered

The dongle disassembles cleanly (load base `0x080E2000`, found from the vector
table). The one function that sends an interrupt-IN report to the host has no
indirect callers, so its full caller list is authoritative. Its callers are an
init-time announcement and the consumer-control (`0x0C`) media-key path only.
The 2.4 GHz link handler (`bt_rx_notify_hb`) updates a cached copy of the
headset state in RAM and never calls the sender.

So a boom or mute change updates the dongle's cache silently and is never pushed
to the host. There is no subscribe or enable-notification command. Polling is
the only option, which is why the Smart Mic polls.

A patch could reuse the existing `0x0C` push path, hooking the cache-update site
to emit a report when boom or mute changes. That would be a small change.

### No secure boot

The boot chain verifies a hash and symmetric encryption, not a signature. The
preloader and app have no RSA or ECDSA code; integrity is SHA-256 plus CRC. The
researchers behind CVE-2025-20700 bricked these devices by flashing bad images,
which proves the device boots unsigned images. So a modified image is accepted
if it is encrypted with the known key and its hashes are recomputed.

Nothing in the firmware disables the SWD debug port; the app actively uses the
debug subsystem for its own crash handling and defers to an attached debugger.
The one unknown is a factory eFuse read by the mask-ROM BootROM, which no
firmware partition can reveal. The eFuse state is confirmable only by probing
the chip, and a read-only SWD IDCODE probe does that with no risk.

### Patching is gated on two unknowns

A firmware patch to push boom/mute state is more feasible than expected (no
signature wall, known key, small change, exposed debug pads), but not something
to attempt until both of these are settled:

1. **Repack acceptance.** The `fota-tool/` rebuild is valid by construction (all
   hashes recomputed, correct AES/LZMA) but is not byte-identical to the vendor
   image, because liblzma is a different LZMA encoder than Airoha's. Whether the
   device accepts it comes down to whether the bootloader checks only the hashes
   (which are recomputed correctly) or also expects the vendor's exact bytes.
   All evidence points to hash-only acceptance, but it can only be settled on the
   device. The safe way to settle it is to flash an **unmodified** rebuild first:
   unpack and repack the stock firmware with no patch, so the only change is the
   re-compression. If that boots, acceptance is hash-based and any size-preserving
   patch will work. If it bricks, acceptance needs byte-identity and the patch
   route is dead. Do this no-op test before ever flashing a real patch, and only
   after gate 2.
2. **Recovery.** A bad flash likely bricks the dongle, and the dongle is the only
   thing that pairs with the headset. Recovery depends on the SWD port being
   open (the eFuse unknown above) or a BootROM download mode existing. Confirm a
   working read/write SWD path, and keep a known-good flash dump, before flashing
   anything.

A further unknown for a real patch: a patch that grows the compressed payload
may exceed a partition's flash region (the `0x12` table spacing). Size-preserving
decompressed patches avoid it. The global `0x00` hash is the only hash over the
ciphertext and is recomputed, so re-encryption needs no other fix-up.

Until both gates hold, the deployed poll-based Smart Mic is the answer and the
firmware work stays understanding-only.
