# Onboarding a new host into the homelab

Checklist for bringing a new machine into the fleet. Living doc — expand as gaps
show up. Steps are roughly ordered; the SSH-CA enrollment (step 7) is the one
that's easy to forget and has a timing constraint, so it's spelled out in full.

## 1. Define the host

- [ ] Create `modules/hosts/<hostname>/default.nix`.
- [ ] Declare the host: `den.hosts.<system>.<hostname> = { role = "server" | "workstation"; ... }`.
- [ ] Add host-specific config under `den.aspects.<hostname>.nixos = { ... }: { ... }`.
- [ ] `network`: `mode = "static"` (servers — set `interfaces.<if>.address`/`gateway`)
      or `"dynamic"` (laptops).

## 2. Hardware

- [ ] `hardware.nix` (or inline) — filesystems, kernel modules, firmware.
- [ ] Servers: `disko.nix` for declarative partitioning.
- [ ] Set `system.stateVersion`.

## 3. SSH identity

- [ ] `ssh.enable = true`.
- [ ] `ssh.hostKey = "ssh-ed25519 AAAA…";` — the host's real ed25519 host key.
      Get it from the running host: `cat /etc/ssh/ssh_host_ed25519_key.pub`
      (drop the trailing `user@host` comment), or `ssh-keyscan -t ed25519 <host>`.

## 4. Register & track

- [ ] Update `homelab.toml` if the host needs an entry (metadata, keys).
- [ ] `git add` every new file — Nix flakes only see git-tracked files.

## 5. Validate

- [ ] `prek run -a` (deadnix, statix, treefmt, etc.).
- [ ] `nix eval .#nixosConfigurations.<hostname>.config.system.build.toplevel.drvPath`
      to confirm it evaluates.

## 6. Deploy

- [ ] Deploy the config (`./deploy.sh <hostname> <user@ip>` or `nixos-rebuild
      switch --flake .#<hostname>`).

## 7. Enroll into the SSH CA  ⚠️ timing matters

The fleet serves self-renewed host certs (`fleet.ssh.serveRenewedHostCert = true`).
A host that isn't enrolled has no cert to serve, so it falls back to its raw host
key (a TOFU prompt — not broken, `authorized_keys` login still works, just not
cert-verified). **Enroll around the same time as the first deploy** so the gap is
brief. Enroll is one-time; the host self-renews daily thereafter (SSHPOP, no
secret). See `docs/pi-ca-secrets-plan.md` for the why.

1. On **strontium** (the CA), mint a one-time token + print the host command:
   ```bash
   sudo ca-enroll-host <hostname>
   ```
2. Paste the printed command on the **new host**. It copies the host pubkey into
   `/var/lib/step-ssh/`, signs it with the token, and starts the renewer:
   ```bash
   sudo install -d -m0755 /var/lib/step-ssh \
   && sudo cp /etc/ssh/ssh_host_ed25519_key.pub /var/lib/step-ssh/ssh_host_ed25519_key.pub \
   && sudo step ssh certificate --host --sign --force --token '<TOKEN>' \
        --ca-url https://ca.gio.ninja --root /etc/step/ca-root.crt \
        <hostname> /var/lib/step-ssh/ssh_host_ed25519_key.pub \
   && sudo systemctl restart ssh-host-cert-renew.service
   ```
3. Verify on the new host:
   ```bash
   ssh-keygen -L -f /var/lib/step-ssh/ssh_host_ed25519_key-cert.pub \
     | grep -E "Type|Valid|Principals|Signing"
   systemctl status ssh-host-cert-renew --no-pager | head -4
   ```
   Expect a `host certificate`, ~30-day validity, principals `<hostname>` +
   `<hostname>.gio.ninja`, and the renewer `Finished`.

## 8. Secrets and the NFS mesh

Secrets reach a host only via agevault — nothing is generated on the box. Add each
one to the offline vault under a **snake_case** name, regenerate the manifest, and
push:

```bash
agevault write <hostname> <secret_name> -
agevault generate-toml
agevault push <hostname>
```

`secrets.toml` has to be committed, or the build fails: `fleet.credentials`
asserts at eval time that every declared need is in the manifest for that host.

- [ ] If the host joins the **NFS mesh**, mint its WireGuard keypair by hand and
      add both halves to the vault:
      ```bash
      priv=$(wg genkey); pub=$(printf '%s' "$priv" | wg pubkey)
      printf '%s' "$priv" | agevault write <hostname> wg_nfs_priv_<hostname> -
      printf '%s' "$pub"  | agevault write <hostname> wg_nfs_pub_<hostname>  -
      ```
      The public half also has to reach every peer, so push it to them too. This
      used to be automatic — `fleet.secrets` generated the keypair and pushed the
      public half — but generators were removed with the credsync teardown. It is
      the one real cost of that change.

## 9. Final checks

- [ ] `ssh <hostname>` connects **cert-verified** (no TOFU prompt).
- [ ] `systemctl list-timers ssh-host-cert-renew` shows the daily renewal scheduled.
- [ ] Host-specific services (DNS/Consul registration, reverse proxy, backups)
      wired per `CLAUDE.md` "Adding a New Service".
