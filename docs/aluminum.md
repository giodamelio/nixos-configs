# Set up aluminum, the Pixel 7 aarch64 builder

**aluminum** is a den host whose NixOS system runs in a chroot on a spare,
rooted Pixel 7 (codename **panther**: Tensor G2, 8 cores, 8 GB RAM). It builds
aarch64 natively, so Pi builds stop going through qemu on cadmium. This plan
roots the phone, bootstraps the chroot, deploys the system, and makes it a
remote builder like any den host with `remoteBuilder.enable`.

Mainline Linux (postmarketOS, Mobile NixOS) isn't realistic on Tensor yet, so
this stays on Android: root with Magisk, then a chroot. Android's `init` stays
PID 1, so NixOS services don't run under systemd. A small start script runs
NixOS activation and starts sshd and nix-daemon itself (section 9).

**Step 3 wipes the phone.**

## 0. Prepare cadmium

```bash
nix shell nixpkgs#android-tools     # adb + fastboot
mkdir -p ~/nixos-configs/tmp/pixel7  # tmp/ is gitignored
```

If `adb devices` or `fastboot devices` says "no permissions", run commands with
`sudo env "PATH=$PATH" …`. Plain `sudo` drops the `nix shell` PATH, and
`flash-all.sh` then fails with a misleading "fastboot too old".

## 1. Prepare the phone

1. Enable developer options: tap **Build number** 7 times.
2. In *Settings → System → Developer options*, turn on **OEM unlocking** and
   **USB debugging**. If OEM unlocking is greyed out, the unit can't be unlocked
   (carrier-locked).
3. Run `adb devices` and accept the prompt on the phone. It should list `device`.

## 2. Download the factory image and Magisk

The phone gets a full factory image after unlocking, so its current build
doesn't matter. Pick the build you'll stay on: Pixel anti-rollback may refuse
older bootloaders once a newer one is flashed.

- **Factory image:** in the **panther** section of
  developers.google.com/android/images, use the **Link** column, not "Flash".
  As of 2026-10, Magisk's stable release supports up to Android 16 QPR2. Android
  17 needs the v31 pre-release, and there's an open boot-failure report for the
  Pixel 7 on 17. This phone runs **16.0.0 (CP1A.260405.005)**.
- **Magisk:** the **v30.7** APK from github.com/topjohnwu/Magisk/releases.
  Compare its SHA-256 with the digest GitHub lists for the asset.

```bash
cd ~/nixos-configs/tmp/pixel7
sha256sum panther-*-factory-*.zip Magisk-v30.7.apk   # compare with the published values
unzip panther-*-factory-*.zip
cd panther-*/
unzip image-panther-*.zip init_boot.img
cp init_boot.img init_boot.stock.img                  # pristine copy for recovery
```

An all-zeros-looking checksum (`e3b0c442…`) means the download is still empty.

## 3. Unlock the bootloader and flash Android (wipes the phone)

```bash
adb reboot bootloader
fastboot flashing unlock     # volume keys -> "Unlock the bootloader", then power
./flash-all.sh               # from the panther-* directory
```

If the phone boots to setup after the unlock, power off and hold
**power + volume down** to get back to the bootloader before `flash-all.sh`.
These warnings from `flash-all.sh` are normal: "Erase successful, but not
automatically formatting", "partition not found: cache", "skip copying … avb
footer", "archive does not contain '*.sig'".

Then do a minimal setup, re-enable developer options and **USB debugging**, and
check the build:

```bash
adb kill-server; adb devices          # restart adb if the phone doesn't show up
adb shell getprop ro.build.id         # must match the factory image
```

## 4. Patch init_boot with Magisk

```bash
adb install ../Magisk-v30.7.apk
adb push init_boot.img /sdcard/Download/
```

In Magisk, use **Install → Select and Patch a File** on `Download/init_boot.img`.
Decline any offer to update Magisk. Then:

```bash
adb shell ls /sdcard/Download/
adb pull /sdcard/Download/magisk_patched-30700_XXXXX.img .
```

## 5. Flash it

```bash
adb reboot bootloader
fastboot flash init_boot magisk_patched-30700_XXXXX.img
fastboot reboot
```

Open Magisk. If it asks for additional setup, let it reboot.

## 6. Verify root

```bash
adb shell su -c id     # approve on the phone; expect uid=0(root) … context=u:r:magisk:s0
```

Magisk's **Install** button stays visible even when root works; the *Magisk*
card reading **Installed: 30.7 (30700)** is the real indicator.

## 7. Keep root stable

- **Turn off automatic updates** (*Developer options → Automatic system updates*).
  An over-the-air update replaces `init_boot` and silently removes root. To update
  on purpose, flash the new factory image and re-patch its `init_boot.img`.
- **Never relock** (`fastboot flashing lock`) with a modified image flashed; it
  can brick the phone.
- **If it boot-loops,** hold **power + volume down**, then
  `fastboot flash init_boot init_boot.stock.img`.
- Keep `tmp/pixel7/` (factory folder, stock `init_boot`); it's the recovery kit.

## 8. Set the phone up as an appliance

- *Settings → Battery → Charging optimization → **Limit to 80%***. It stays on
  the charger permanently, and capping the charge keeps the battery from swelling.
- *Developer options → **Stay awake*** (screen on while charging). This keeps
  doze from throttling it.
- Take it out of its case, stand it upright, and give it airflow. Sustained
  builds throttle on heat.
- Give it a fixed address: either a DHCP reservation for its Wi-Fi MAC on the
  UniFi controller (turn off MAC randomization for that network first), or a
  USB-C Ethernet adapter.

## 9. How aluminum is put together

aluminum is a normal den host (`modules/hosts/aluminum/`) whose NixOS system
runs in a chroot at `/data/local/aluminum`. Android's `init` stays PID 1, so
nothing runs as a systemd service. Two pieces from `modules/packages/aluminum/`
stand in for what systemd would do:

- **`aluminum-bootstrap`**: the first-install tarball. It holds an aarch64 Nix
  store, nix-daemon, and sshd with root login for `homelab.ssh_keys`; just
  enough to receive the real system. cadmium only *downloads* the aarch64
  binaries from cache.nixos.org and packs them, so building it needs no aarch64
  builder.
- **`/aluminum/up`** (in the tarball) runs on Android. It sets SELinux
  permissive, bind-mounts `/dev`, `/dev/pts`, `/proc` and `/sys`, mounts a fresh
  `/run`, then chroots into `/aluminum/inside-start`.
- **`/aluminum/inside-start`** runs in the chroot, as root. On first run, it
  loads the store database. Once a system is deployed, it hands over to that
  system's `aluminum-start`. Before then, it starts the bootstrap's sshd and
  nix-daemon.
- **`aluminum-start`** is part of the deployed system, so it changes with
  every deploy:
  1. It gives `/run/wrappers` a `suid` bind mount from `/var/lib/aluminum/wrappers`.
     The security wrappers need a filesystem with extended attributes, and
     Android's tmpfs has none. `/data` itself is `nosuid`.
  2. It runs NixOS's own `activate`, the same way `nixos-enter` does. That sets
     up users, `/etc`, `/run/current-system` and the setuid wrappers. Activation
     errors are reported but don't stop it.
  3. It makes sure an ed25519 host key exists.
  4. It starts nix-daemon and sshd. They log to `/var/log/aluminum/`, since the
     chroot has no syslog.
- **`aluminum-deploy`** replaces `switch-to-configuration`, which needs systemd.
  It builds `nixosConfigurations.aluminum`, copies it over, sets the system
  profile, and runs the new system's `aluminum-start --restart`.

What the den host sets:
- `boot.isContainer`, with `NIX_REMOTE` reset to `auto`. The container default
  assumes the host's daemon.
- The sandbox is off.
- Users are immutable, so the bootstrap's seed `/etc/shadow` never wins.
- Root can log in with your keys, for `aluminum-deploy`. `server` and sudo work
  as on any host.
- Chroot accounts are in the OEM-reserved uid range (`server` 5001,
  `nix-remote-builder` 5000).
- The nixbld users are in `aid_inet`/`aid_net_raw`. Android only lets those
  groups open sockets ("paranoid networking").

PAM needs the setuid wrappers. With SELinux on, `pam_unix` checks every account
through the `unix_chkpwd` wrapper. Without it, sshd refuses every login with
"Access denied … by PAM account configuration".

Run commands on the phone as `adb shell "su -c '…'"`. Without the outer double
quotes, the local shell splits the command and parts of it run as the `shell`
user.

## 10. Bootstrap the chroot

On cadmium:

```bash
cd ~/nixos-configs
nix build .#aluminum-bootstrap
adb push result/tarball/aluminum-bootstrap.tar.gz /data/local/tmp/
adb shell "su -c 'mkdir -p /data/local/aluminum && cd /data/local/aluminum && tar -xzpf /data/local/tmp/aluminum-bootstrap.tar.gz && rm /data/local/tmp/aluminum-bootstrap.tar.gz && sh /data/local/aluminum/aluminum/up'"
adb shell "su -c 'cat /data/local/aluminum/etc/ssh/ssh_host_ed25519_key.pub'"
```

Check that SSH works with your normal key:

```bash
ssh root@<phone-ip> /sw/bin/nix --version
```

## 11. Deploy the NixOS system

`nixosConfigurations.aluminum` has aarch64 build steps, so build it on an
aarch64 builder. Use oganesson, or, once bootstrapped, aluminum itself
(`ssh-ng://root@<phone-ip>`). From the repo root:

```bash
nix run .#aluminum-deploy -- root@<phone-ip> \
  --max-jobs 0 \
  --builders 'ssh-ng://nix-remote-builder@165.1.77.252 aarch64-linux /root/.ssh/nix-remote-builder 2 1 big-parallel'
```

Once cadmium runs `remote-builder-user` with oganesson listed, the
`--builders`/`--max-jobs` flags aren't needed.

Afterwards, `ssh server@<phone-ip>` works like on any other host, and
`ssh root@<phone-ip>` too.

## 12. Make it a remote builder

In `modules/hosts/aluminum/default.nix`:

1. Set `ssh.hostKey` to the key printed in step 10.
2. Set `remoteBuilder.hostName` to the phone's reserved LAN address.
3. Set `remoteBuilder.enable = true`.

Then redeploy aluminum (step 11), so it gets `nix-remote-builder`, and redeploy
cadmium, so its `remote-builder-user` lists aluminum.

## 13. Start it at boot

Magisk runs scripts in `/data/adb/service.d/` after boot:

```bash
printf '#!/system/bin/sh\nsleep 30\ncmd wifi force-low-latency-mode enabled\nsh /data/local/aluminum/aluminum/up\n' > tmp/aluminum.sh
adb push tmp/aluminum.sh /data/local/tmp/
adb shell "su -c 'mv /data/local/tmp/aluminum.sh /data/adb/service.d/ && chmod 0755 /data/adb/service.d/aluminum.sh'"
```

The 30-second sleep lets `/data` and the network settle.

Low-latency mode turns off Wi-Fi power saving, which resets at every boot.
Without it, the radio dozes when idle, and the first packets after a quiet
period take hundreds of milliseconds.

## 14. Update it later

Run `aluminum-deploy` again. The start logic ships with the system, so the
bootstrap rarely needs updating.

If `inside-start` does change, copy only that file. Re-extracting the whole
tarball over a deployed system would overwrite its `/etc/passwd`, `shadow` and
`sshd_config`:

```bash
nix build .#aluminum-bootstrap
tar -xzOf result/tarball/aluminum-bootstrap.tar.gz --wildcards '*aluminum/inside-start' \
  | ssh root@<phone-ip> 'cat > /aluminum/inside-start && chmod 0755 /aluminum/inside-start'
```

## Open questions to check while doing it

- Whether the Nix sandbox works on this kernel. Try `sandbox = true` once; if
  builds fail with namespace errors, keep it off.
- Whether Android's doze still cuts Wi-Fi with *Stay awake* on. If builds drop
  mid-way, switch to a USB-C Ethernet adapter.
- Whether SELinux needs to stay permissive, or whether a Magisk module can scope
  the exceptions instead of `setenforce 0`.
- Whether builds need `/dev/shm`. Android may not have one; if a build asks
  for it, mount a tmpfs at `/dev/shm` in `up`.
