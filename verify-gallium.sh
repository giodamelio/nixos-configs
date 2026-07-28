#!/usr/bin/env bash
# READ-ONLY verification for gallium (NFS server). Run on cadmium; SSHes in as
# server@ and observes via sudo. Restarts nothing, starts nothing.
# Investigate any line with: MISSING / FAILED / NO / degraded.
set -uo pipefail

ssh -o ConnectTimeout=10 server@gallium.gio.ninja 'sudo bash -s' <<'EOF'
set -uo pipefail
echo "########## GALLIUM (NFS server) ##########"
echo "-- system state --";  systemctl is-system-running || true
echo "-- failed units --";  systemctl --failed --no-legend | grep . || echo "(none)"
echo
echo "-- wg tunnel --";      wg show wg-nfs | grep -E 'interface|peer|endpoint|latest handshake|transfer' || echo "NO WG"
echo "-- ping carbon (10.200.0.2) --"; ping -c2 -W3 10.200.0.2 >/dev/null && echo "ping OK" || echo "PING FAILED"
echo
echo "-- nfs-server --";     systemctl is-active nfs-server.service
echo "-- exports --";        exportfs -s 2>/dev/null || echo "NO EXPORTS"
echo
echo "-- credstore blobs --"; ls /usr/lib/credstore.encrypted/ | grep -E 'wg-nfs' || echo "MISSING blobs"
echo "-- host cert deployed --"; if test -e /etc/ssh/ssh_host_ed25519_key-cert.pub; then ssh-keygen -Lf /etc/ssh/ssh_host_ed25519_key-cert.pub | grep -E 'Type|Valid|Principals'; else echo "NO HOST CERT"; fi
echo "-- peer push key authorized --"; grep -o 'credsync-push@[a-z]*' /etc/ssh/authorized_keys.d/server 2>/dev/null || echo "NO PUSH KEY AUTHORIZED"
echo "-- pending secrets --"; cat /run/issue.d/fleet-secrets.issue 2>/dev/null || echo "(none)"
EOF
