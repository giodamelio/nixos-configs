#!/usr/bin/env nu

# Edit a systemd-creds encrypted credential file in place.
#
# Decrypts the credential into a RAM-backed temporary directory, opens it in
# $EDITOR, then re-encrypts and atomically writes the result back into place.
# If the given path does not exist, starts from an empty buffer and creates a
# new encrypted credential there.
#
# The plaintext never touches persistent storage: the temp dir lives on tmpfs
# (/dev/shm, /run, or $XDG_RUNTIME_DIR) so the decrypted secret -- and any
# editor swap/backup files created next to it -- stay in memory and are wiped
# on exit. (Note: tmpfs can still be paged to swap unless swap is encrypted or
# disabled.)
#
# Requires root: reading /etc/credstore.encrypted and the host credential key
# at /var/lib/systemd/credential.secret both need privileges.
def main [
    path: path # Full path to the encrypted credential file (e.g. /etc/credstore.encrypted/foo)
    --name (-n): string # Credential name to embed/validate (default: the filename)
    --with-key (-k): string = "auto" # Key to encrypt with: auto, host, tpm2, host+tpm2, null
    --editor (-e): string # Editor command to use (default: $env.EDITOR, $env.VISUAL, then vi)
] {
    # systemd-creds needs root for the credstore and the host key.
    if (^id -u | str trim) != "0" {
        error make {msg: "Must run as root (try: sudo systemd-creds-edit ...)"}
    }

    # A missing path means "create a new credential here".
    let creating = (not ($path | path exists))
    let path = ($path | path expand)
    let cred_name = ($name | default ($path | path basename))

    # Preserve the original permissions on edit; default to 0600 when creating.
    let orig_mode = if $creating { "600" } else { (^stat -c "%a" $path | str trim) }

    # Resolve the editor; support commands with arguments like "code --wait".
    let editor_str = ($editor | default ($env.EDITOR? | default ($env.VISUAL? | default "vi")))
    let editor_parts = ($editor_str | split row " " | where ($it | is-not-empty))

    # Create the working dir on the first writable tmpfs-backed location. Keeping
    # it on tmpfs is what keeps the plaintext out of persistent storage.
    let candidates = (
        ["/dev/shm" "/run" $env.XDG_RUNTIME_DIR? "/tmp"]
        | where ($it | is-not-empty)
        | where ($it | path exists)
    )
    mut tmpdir = ""
    for c in $candidates {
        let r = (do { ^mktemp -d -p $c "systemd-creds-edit.XXXXXX" } | complete)
        if $r.exit_code == 0 {
            $tmpdir = ($r.stdout | str trim)
            break
        }
    }
    if ($tmpdir | is-empty) {
        error make {msg: $"Could not create a temp dir in any of: ($candidates | str join ', ')"}
    }
    let tmpdir = $tmpdir
    ^chmod 700 $tmpdir
    let tmpfile = ($tmpdir | path join $cred_name)

    # Run everything under try so the plaintext temp dir is always wiped.
    try {
        if $creating {
            # Start from an empty buffer for a brand-new credential.
            ^touch $tmpfile
        } else {
            # Decrypt into the temp file, validating the embedded name.
            ^systemd-creds decrypt $"--name=($cred_name)" $path $tmpfile
        }
        ^chmod 600 $tmpfile

        # Hash before/after so we can skip a pointless re-encrypt.
        let before = (open --raw $tmpfile | hash sha256)

        ^($editor_parts | first) ...($editor_parts | skip 1) $tmpfile

        let after = (open --raw $tmpfile | hash sha256)

        if $before == $after {
            if $creating {
                print "No content entered; nothing written."
            } else {
                print "No changes; leaving the encrypted file untouched."
            }
        } else {
            # Encrypt to a temp blob first, then move into place atomically so a
            # failed encryption can never corrupt the original.
            let newblob = ($tmpdir | path join $"($cred_name).new")
            (
                ^systemd-creds encrypt
                    $"--name=($cred_name)"
                    $"--with-key=($with_key)"
                    $tmpfile
                    $newblob
            )
            # Make sure the destination directory exists when creating.
            mkdir ($path | path dirname)
            mv -f $newblob $path
            ^chmod $orig_mode $path
            if $creating {
                print $"Created ($path)"
            } else {
                print $"Re-encrypted and wrote ($path)"
            }
        }
    } catch {|err|
        rm -rf $tmpdir
        error make {msg: $"systemd-creds-edit failed: ($err.msg)"}
    }

    rm -rf $tmpdir
}
