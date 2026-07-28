#!/usr/bin/env bash
# READ-ONLY verification for carbon (NFS client). Run on cadmium; SSHes in as
# server@ and observes via sudo. Restarts nothing, starts nothing.
# Investigate any line with: MISSING / FAILED / NO / degraded / NOT readable.
set -uo pipefail

ssh -o ConnectTimeout=10 server@carbon.gio.ninja 'sudo bash -s' <<'EOF'
set -uo pipefail
echo "########## CARBON (NFS client) ##########"
echo "-- system state --";  systemctl is-system-running || true
echo "-- failed units --";  systemctl --failed --no-legend | grep . || echo "(none)"
echo
echo "-- wg tunnel --";      wg show wg-nfs | grep -E 'interface|peer|endpoint|latest handshake|transfer' || echo "NO WG"
echo "-- ping gallium (10.200.0.1) --"; ping -c2 -W3 10.200.0.1 >/dev/null && echo "ping OK" || echo "PING FAILED"
echo
echo "-- nfs mounts --";     findmnt -nt nfs4 || echo "NO NFS MOUNTS"
echo "-- read test --";      { ls /mnt/forgejo-repos   >/dev/null 2>&1 && echo "forgejo-repos readable"   || echo "forgejo-repos NOT readable"; }
                             { ls /mnt/paperless-media >/dev/null 2>&1 && echo "paperless-media readable" || echo "paperless-media NOT readable"; }
echo
echo "-- zwave-js --";       systemctl is-active zwave-js.service
echo "-- gradient (expect masked x3) --"; systemctl is-enabled gradient-server.service gradient-worker.service gradient-deployer.service 2>&1 | tr '\n' ' '; echo
echo
echo "-- credstore blobs --"; ls /usr/lib/credstore.encrypted/ | grep -E 'wg-nfs|zwavejs' || echo "MISSING blobs"
echo "-- host cert deployed --"; if test -e /etc/ssh/ssh_host_ed25519_key-cert.pub; then ssh-keygen -Lf /etc/ssh/ssh_host_ed25519_key-cert.pub | grep -E 'Type|Valid|Principals'; else echo "NO HOST CERT"; fi
echo "-- peer push key authorized --"; grep -o 'credsync-push@[a-z]*' /etc/ssh/authorized_keys.d/server 2>/dev/null || echo "NO PUSH KEY AUTHORIZED"
echo "-- pending secrets --"; cat /run/issue.d/fleet-secrets.issue 2>/dev/null || echo "(none)"
EOF
