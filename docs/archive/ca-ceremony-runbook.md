# CA key ceremony — strontium (Phase 1)

One-time generation of the CA key material on strontium. Produces the offline
X.509 root (backed up + wiped) + the operational intermediate + the SSH user/host
CAs. See `docs/pi-ca-secrets-plan.md` for the why. **step-ca wiring is a separate
phase** — this only makes and backs up keys.

Params (confirmed): EC **P-256**; root CN **`Gio Homelab Root CA`** (20y =
`175200h`); intermediate CN **`Gio Homelab Intermediate CA`** (10y = `87600h`).

Recipient set = `ca-recovery-recipients.txt` (YubiKey A + B + paper recovery).
**The YubiKeys do NOT need to be plugged into strontium** — encrypting *to* the
recipients uses only their public keys. (If `age` errors about a plugin, plug one
in; but it shouldn't.)

## 0. Prep on strontium
```bash
# tools (aarch64, from cache)
nix shell nixpkgs#step-cli nixpkgs#age nixpkgs#age-plugin-yubikey nixpkgs#paper-age nixpkgs#openssh

# recipients file onto strontium (it's public — scp from cadmium or via the USB)
#   e.g. from cadmium:  scp ca-recovery-recipients.txt server@10.30.0.13:

# mount the USB (find it first)
lsblk
sudo mkdir -p /mnt/usb && sudo mount /dev/sdX1 /mnt/usb   # <- real device from lsblk

# tmpfs workdir (RAM — the root key never touches the SD)
mkdir -m700 /dev/shm/ceremony && cd /dev/shm/ceremony
cp ~/ca-recovery-recipients.txt ./recipients.txt
```

## 1. X.509 root (in tmpfs)
```bash
step certificate create "Gio Homelab Root CA" root.crt root.key \
  --profile root-ca --kty EC --curve P-256 --not-after 175200h \
  --no-password --insecure
```

## 2. X.509 intermediate (signed by the root)
```bash
step certificate create "Gio Homelab Intermediate CA" intermediate.crt intermediate.key \
  --profile intermediate-ca --ca root.crt --ca-key root.key \
  --kty EC --curve P-256 --not-after 87600h --no-password --insecure

step certificate verify intermediate.crt --roots root.crt && echo "chain OK"
```
(No password on the intermediate key for now; the step-ca wiring phase handles the
module's password-file expectation.)

## 3. SSH user + host CA keypairs (stay on strontium; ed25519)
```bash
ssh-keygen -t ed25519 -f ssh_user_ca -C "Gio Homelab SSH User CA" -N ""
ssh-keygen -t ed25519 -f ssh_host_ca -C "Gio Homelab SSH Host CA" -N ""
```

## 4. Back up every private key to the USB (age)
```bash
for k in root.key intermediate.key ssh_user_ca ssh_host_ca; do
  age -R recipients.txt -o "/mnt/usb/$k.age" "$k"
done
# public bits too (plaintext, handy to have on the USB)
cp root.crt intermediate.crt ssh_user_ca.pub ssh_host_ca.pub /mnt/usb/
```

## 5. Paper backup of the ROOT key
`paper-age` encrypts, so the PDF is safe to move to a printer host:
```bash
paper-age -t "Gio Homelab Root CA key" -o /mnt/usb/root-key.pdf root.key
```
Then print `root-key.pdf` from a machine with a printer (e.g. copy the USB to
cadmium and `lp` it) → into the safe. The plaintext `root.key` never leaves
strontium's tmpfs.

## 6. ⚠️ VERIFY BACKUPS BEFORE WIPING (the root is irreplaceable)
- The four `.age` files exist on the USB and are non-trivial size (`ls -l /mnt/usb`).
- Strong check: copy `/mnt/usb/root.key.age` to cadmium and prove it decrypts
  with **YubiKey A**: `age -d -i ~/yubikey-a.identity root.key.age | head -c 60`.
- The printed `root-key.pdf` QR actually scans.

Do **not** proceed to the wipe until the root backup is confirmed good.

## 7. Stage the operational keys on strontium (persistent)
Everything except the root **key** stays on the box for step-ca:
```bash
sudo install -d -m700 /var/lib/gio-ca
sudo cp intermediate.key intermediate.crt root.crt \
        ssh_user_ca ssh_user_ca.pub ssh_host_ca ssh_host_ca.pub /var/lib/gio-ca/
sudo chmod 600 /var/lib/gio-ca/{intermediate.key,ssh_user_ca,ssh_host_ca}
```
(`root.crt` is the public trust anchor — kept; distributed to the fleet later. The
root **key** is NOT copied here.)

## 8. Wipe the root plaintext from strontium
```bash
cd / && shred -u /dev/shm/ceremony/* 2>/dev/null; rm -rf /dev/shm/ceremony
sudo umount /mnt/usb
```
Store the USB (age-encrypted keys) and the printed root paper offline in the safe.

## Result
- **strontium `/var/lib/gio-ca/`:** intermediate key+cert, root.crt, SSH user/host CA keys.
- **USB (offline):** `*.age` of all four private keys + the public certs + the root paper PDF.
- **safe:** printed root-key paper.
- Root **private** key exists **only** in the age backups + paper — never on the SD.

## Next phase (not this runbook)
Wire `services.step-ca` to read the intermediate + SSH CA keys from
`/var/lib/gio-ca`, add the JWK provisioner, distribute the public trust anchors
(root.crt, ssh_user_ca.pub, ssh_host_ca.pub) to the fleet, mint the first host +
user certs.
