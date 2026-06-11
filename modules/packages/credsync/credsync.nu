#!/usr/bin/env nu

# credsync: idempotently copy systemd credentials between hosts over SSH.
#
# A credential is generated on one host (into the encrypted credstore) and
# pushed to the hosts that consume it. Encrypted blobs are bound to the local
# host key/TPM, so they cannot be compared or copied as-is across machines --
# instead the sender always transmits the plaintext (inside the SSH channel)
# and the RECEIVER does change detection: it decrypts its existing credential,
# compares plaintexts, and only re-encrypts + signals consumers when the value
# actually changed. Running a push twice is therefore a no-op.
#
# The plaintext only ever travels through stdin/pipes; never on argv, never
# unencrypted on disk.

# Where encrypted credentials live (systemd's credstore search path).
def credstore-dir [] {
    $env.CREDSTORE_DIR? | default "/usr/lib/credstore.encrypted"
}

# Extra args for systemd-creds, e.g. "--with-key=auto" for TPM-less testing.
def creds-args [] {
    $env.CREDSYNC_CREDS_ARGS? | default "" | split row " " | where ($it | is-not-empty)
}

# Credential names end up in paths and systemd unit names; keep them tame.
def check-name [name: string] {
    if not ($name =~ '^[a-zA-Z0-9_.-]+$') {
        error make {msg: $"invalid credential name: ($name)"}
    }
}

def decrypt-cred [name: string, path: path] {
    do { ^systemd-creds decrypt ...(creds-args) $"--name=($name)" $path - } | complete
}

# Receive a credential on stdin and store it in the local credstore.
# Normally invoked remotely by `credsync push`. Prints "unchanged" or "updated".
def "main write" [
    name: string # Credential name
    ...restart_units: string # Units to try-restart when the credential changed
] {
    check-name $name
    # Stdin reaches $in because the wrapper runs nu with --stdin.
    let incoming = $in
    if ($incoming | is-empty) {
        error make {msg: "no secret provided on stdin"}
    }
    let dir = (credstore-dir)
    let path = ($dir | path join $name)

    # Receiver-side change detection: compare plaintexts. A failed decrypt
    # (corrupt or foreign blob) counts as changed and gets overwritten.
    if ($path | path exists) {
        let existing = (decrypt-cred $name $path)
        if $existing.exit_code == 0 and $existing.stdout == $incoming {
            print "unchanged"
            return
        }
    }

    mkdir $dir
    # Encrypt to a sibling temp file, then move into place atomically so a
    # failed encryption can never corrupt the existing credential.
    let tmp = (^mktemp -u -p $dir $"($name).XXXXXX" | str trim)
    $incoming | ^systemd-creds encrypt ...(creds-args) $"--name=($name)" - $tmp
    ^chmod 600 $tmp
    mv -f $tmp $path

    # Best-effort: the per-credential target only exists once an aspect
    # defines it; consumers use it to gate on the credential's presence.
    let _ = (do { ^systemctl start $"credsync-($name).target" } | complete)

    for unit in $restart_units {
        ^systemctl try-restart $unit
    }
    print "updated"
}

# Push a local credential to another host over SSH.
def "main push" [
    name: string # Credential name (must exist in the local credstore)
    destination: string # SSH destination, e.g. root@host.gio.ninja
    ...restart_units: string # Units the receiver should try-restart on change
] {
    check-name $name
    let path = ((credstore-dir) | path join $name)
    if not ($path | path exists) {
        error make {msg: $"no such credential: ($path)"}
    }

    # Note: capturing output strips trailing newlines -- fine for tokens,
    # byte-exact binary credentials are out of scope.
    let local = (decrypt-cred $name $path)
    if $local.exit_code != 0 {
        error make {msg: $"failed to decrypt ($path): ($local.stderr | str trim)"}
    }

    # The receiver needs root for the credstore and systemctl, so any non-root
    # login goes through sudo. -n: fail instead of hanging on a password
    # prompt; BatchMode likewise so an automated push can never sit waiting.
    let remote_cmd = if ($destination | str starts-with "root@") {
        [credsync write $name ...$restart_units]
    } else {
        [sudo -n credsync write $name ...$restart_units]
    }

    let pushed = (do { $local.stdout | ^ssh -o BatchMode=yes $destination ...$remote_cmd } | complete)
    if $pushed.exit_code != 0 {
        error make {msg: $"push of ($name) to ($destination) failed: ($pushed.stderr | str trim)"}
    }
    # Relay the receiver's "unchanged"/"updated" verdict.
    print ($pushed.stdout | str trim)
}

def main [] {
    print "credsync - idempotently copy systemd-creds between hosts over SSH"
    print ""
    print "Usage:"
    print "  credsync push <name> <destination> [restart-units...]"
    print "  credsync write <name> [restart-units...]   (reads secret from stdin; used via ssh)"
}
