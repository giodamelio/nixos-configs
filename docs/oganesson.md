# Run oganesson, the Oracle Cloud aarch64 builder

**oganesson** is an Oracle Cloud Ampere A1 VM (2 OCPU, 12 GB, aarch64). It is
the fleet's native ARM builder, so Pi builds don't go through qemu on cadmium,
and it pushes what it builds to `cache.gio.ninja`. Its config is in
`modules/hosts/oganesson/`.

It holds no state of its own:
- **Secrets** come from agevault: `niks3_api_token`, `wireguard_lan_private_key`
  and `healthcheck_url`.
- **Builds** end up in the cache.
- **The config** deploys from `main` through comin.

If the VM is lost, you rebuild it from this page.

## Set up the Oracle Cloud account

The account is on **Pay As You Go**. The A1 shape stays within the Always Free
limits, so it costs nothing as long as nothing else is created. Upgrading also
matters because Oracle may reclaim Always Free instances it considers idle. The
rule is: over 7 days, 95th-percentile CPU under 20%, network under 20% and
memory under 20%. A build box between builds would qualify. Oracle's docs don't
say whether Pay As You Go accounts are exempt, but user reports say they are.
If Oracle ever stops the instance, the heartbeat alerts, and you start it again
from the console. The boot volume survives.

Check the account type under *Billing & Cost Management → Upgrade and Manage
Payment*. Set a small budget alert there too, so a stray paid resource shows up
before the bill does.

## Lay out the network

- **VCN:** `10.250.0.0/16`, with an internet gateway and a default route
  (`0.0.0.0/0`) to it.
- **Public subnet:** `10.250.250.0/24`. oganesson gets its private address here
  by DHCP (`network.mode = "dhcp"`).
- **Public IP:** `165.1.77.252`. It's ephemeral and changes if you recreate the
  instance. The NAT is in front of the VNIC, so the address never appears on the
  interface.
- **Security list ingress:** ICMP only. Port 22 is closed, and SSH goes through
  the LAN VPN (see "Get in when the VPN is down").

OCI security rules are stateful, so the outbound WireGuard connection needs no
inbound rule.

## Install it

Create the instance from Oracle's Ubuntu image (aarch64) with a 150 GB boot
volume, and add your SSH key for the `ubuntu` user. Then, before installing,
open port 22 in the security list for your own IP (see "Get in when the VPN is
down"), and install `cpio` on the Ubuntu side. nixos-anywhere's kexec step needs
it:

```bash
ssh ubuntu@<public-ip> 'sudo apt-get install -y cpio'
```

From the repo root on cadmium:

```bash
nix run github:nix-community/nixos-anywhere -- \
  --flake .#oganesson \
  --target-host ubuntu@<public-ip> \
  --build-on remote \
  --no-use-machine-substituters
```

`--build-on remote` builds the system on the A1 itself, natively.
`--no-use-machine-substituters` keeps nixos-anywhere from passing the target's
cache settings into the installer before the network can reach them.

disko then wipes `/dev/sda` and lays out the disk:
- a 1 GB ESP, with GRUB installed to the removable-media path, because OCI
  firmware doesn't keep NVRAM boot entries reliably;
- a ZFS pool `root`, with datasets for `/`, `/nix` and `/home`, plus a 5 GB
  reserve.

If the install stops after partitioning, rerun it with
`--phases install,reboot`.

After it reboots:
1. Record the new host key in `ssh.hostKey`. Every remote-builder client pins
   it.
2. Push the agevault secrets: `agevault push oganesson`.
3. Deploy once over the public IP, which installs WireGuard.
4. Then continue with "Join the LAN" and the SSH CA enrollment from
   `docs/onboarding-a-host.md`.

## Join the LAN

oganesson is a client of the UniFi WireGuard VPN server. The interface is
`wg-lan`, with address `10.100.0.3`. The client is called `Trusted-Oganesson` in
UniFi, which also routes `10.250.0.0/16` to this peer.

The UniFi client config sends all traffic through the tunnel
(`AllowedIPs = 0.0.0.0/0`). `lan-vpn.nix` uses a split tunnel instead:

- **Routes:** only the LAN subnets `10.0.0.0/16` and `10.30.0.0/24` go through
  the tunnel. IoT (`10.40.0.0/16`) is not routed.
- **DNS:** only `gio.ninja` and `lan` names go to the LAN resolvers.
  `home.gio.ninja`, the tunnel's own endpoint, stays on Oracle's resolver, so
  resolving it never depends on the tunnel. `oganesson.gio.ninja` resolves to
  `10.100.0.3`.
- **Endpoint refresh:** networkd resolves the endpoint only once, so a 5-minute
  timer (`wg-lan-endpoint-refresh`) re-resolves `home.gio.ninja` after a home IP
  change.
- **VCN routing:** traffic from the LAN for `10.250.0.0/16` is forwarded and
  masqueraded. Other VCN hosts need no route back, and nothing is forwarded
  from the VCN into the LAN except replies.

The private key is the agevault secret `wireguard_lan_private_key`, loaded into
`systemd-networkd` as a credential. To replace it, regenerate the client in
UniFi and save it. An unsaved client silently drops the handshakes. Then:

```bash
agevault edit oganesson wireguard_lan_private_key
agevault push oganesson
ssh server@oganesson.gio.ninja 'sudo systemctl restart systemd-networkd && sleep 5 && sudo wg show wg-lan'
```

A working tunnel shows a `latest handshake` line. If `wg show` lists bytes sent
but none received, UniFi doesn't know the client's public key.

## Get in when the VPN is down

sshd is hardened for the internet (`ssh-internet-facing`): key-only logins,
`AllowUsers`, no forwarding, and fail2ban. That lets you open it temporarily:

1. Find your current public IP: `curl -s https://ifconfig.me`.
2. In the subnet's security list, add an ingress rule: source `<your-ip>/32`,
   TCP, destination port 22, description `break glass`.
3. Connect with `ssh server@165.1.77.252`.
4. Delete the rule afterwards.

If sshd itself is broken, use the serial console: *Compute → Instances →
oganesson → Console connection → Launch Cloud Shell connection*. No account has
a password, so pick a boot entry in GRUB and boot into an emergency shell.

To see who has been knocking:

```bash
journalctl -u sshd --since "-7d" --no-pager | grep -oE "Invalid user [^ ]+" | sort | uniq -c | sort -rn | head
sudo fail2ban-client status sshd
```

## Deploy it

comin rebuilds oganesson from `main` on GitHub, so a commit pushed to `main`
deploys itself. A deploy from your working copy (`deploy oganesson`) works too,
but comin reverts it to `main` on its next poll. Push to `main` instead, or
expect the revert.

`deploy oganesson` connects to `server@oganesson.gio.ninja`, over the VPN.

## Know what monitors it

- **Heartbeat:** the fleet's Telegraf heartbeat (`server-heartbeat`) pushes to
  its own Healthchecks check every 4 minutes. It checks disk, zpool, failed
  units, internet and the SSH host cert.
- **SSH host cert:** renewed daily from strontium's CA over the VPN
  (`ssh-host-cert-renew`).
