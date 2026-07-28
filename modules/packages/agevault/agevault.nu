#!/usr/bin/env nu

# agevault: age-backed secret manager for the fleet. Run inside the separate,
# offline secrets repo (never a flake input -- secrets must never reach the Nix
# store). Secrets live at rest as `hosts/<host>/<name>.age`, encrypted to the
# recipient set in `recipients.txt` (YubiKey A/B + paper recovery). Hosts are
# never recipients: we decrypt locally and pipe the plaintext over ssh into
# `systemd-creds encrypt` on the target, so the flake only ever sees names.
#
# The filename sans `.age` IS the systemd credential name, verbatim (incl.
# `secrets.json`) -- there are no `_`<->`-` renames, so the blob is encrypted
# WITH its name and loaded under exactly that id.

# --- repo/config helpers ---------------------------------------------------

# Repo root: the secrets repo checkout. Defaults to the current directory;
# AGEVAULT_ROOT overrides it (used by the tests).
def repo-root [] {
    $env.AGEVAULT_ROOT? | default $env.PWD
}

def config [] {
    let p = (repo-root | path join "config.toml")
    if ($p | path exists) { open $p } else { {} }
}

def recipients-file [] {
    let p = (repo-root | path join "recipients.txt")
    if not ($p | path exists) {
        error make {msg: $"missing recipients file: ($p)"}
    }
    $p
}

# age identities used to decrypt: AGEVAULT_IDENTITY (whitespace-separated) plus
# config.toml `identities`. On real use these are age-plugin-yubikey stubs; the
# tests pass a software identity file.
def identities [] {
    let env_ids = (
        $env.AGEVAULT_IDENTITY?
        | default ""
        | split row --regex '\s+'
        | where ($it | is-not-empty)
    )
    let cfg_ids = (config | get identities? | default [])
    let ids = ($env_ids | append $cfg_ids)
    if ($ids | is-empty) {
        error make {msg: "no age identities configured (set AGEVAULT_IDENTITY or config.toml identities)"}
    }
    $ids
}

def id-args [] {
    identities | each {|p| ["-i" $p]} | flatten
}

# Where generate-toml writes the names-only manifest the flake consumes.
def manifest-path [] {
    let p = ($env.AGEVAULT_MANIFEST? | default (config | get manifest_path? | default null))
    if $p == null {
        error make {msg: "manifest_path not set (config.toml or AGEVAULT_MANIFEST)"}
    }
    $p
}

# systemd credstore search path on the target host.
def credstore-dir [] {
    $env.AGEVAULT_CREDSTORE_DIR? | default "/usr/lib/credstore.encrypted"
}

# ssh destination for a host: config.toml `[destinations]` override, else the
# bare host name (resolved via ssh config / DNS).
def ssh-dest [host: string] {
    let d = (config | get destinations? | default {})
    if ($host in ($d | columns)) { $d | get $host } else { $host }
}

# --- name/path helpers -----------------------------------------------------

# Central credential-name validator (used by every name-taking subcommand --
# update the rule here). Names become filenames and systemd credential ids. Dots
# are allowed (secrets.json); dashes are NOT -- underscores only, so name == id ==
# blob name and there is no `_`<->`-` rename class (see MIGRATION.md).
def check-name [name: string] {
    if ($name | str contains "-") {
        error make {msg: $"invalid credential name '($name)': dashes are not allowed -- use underscores"}
    }
    if not ($name =~ '^[a-zA-Z0-9._]+$') {
        error make {msg: $"invalid credential name '($name)': allowed characters are [a-zA-Z0-9._]"}
    }
}

def check-host [host: string] {
    if not ($host =~ '^[a-z0-9-]+$') {
        error make {msg: $"invalid host name: ($host)"}
    }
}

def secret-path [host: string, name: string] {
    repo-root | path join "hosts" $host $"($name).age"
}

def list-hosts [] {
    let d = (repo-root | path join "hosts")
    if not ($d | path exists) { return [] }
    ls $d | where type == dir | get name | each {|p| $p | path basename } | sort
}

# Credential names for a host: every `hosts/<host>/*.age` (symlinks into
# common/ included -- a shared secret shows up under each consuming host).
def host-secret-names [host: string] {
    let d = (repo-root | path join "hosts" $host)
    if not ($d | path exists) { return [] }
    ls $d
    | get name
    | each {|p| $p | path basename }
    | where ($it | str ends-with ".age")
    | each {|f| $f | str replace --regex '\.age$' '' }
    | sort
}

# Every secret .age file across all hosts (paths, symlinks not yet resolved).
def all-age-files [] {
    list-hosts
    | each {|h|
        ls (repo-root | path join "hosts" $h)
        | get name
        | where ($it | str ends-with ".age")
    }
    | flatten
}

# --- subcommands -----------------------------------------------------------

# Decrypt a secret to stdout.
def "main cat" [host: string, name: string] {
    check-host $host
    check-name $name
    let p = (secret-path $host $name)
    if not ($p | path exists) {
        error make {msg: $"no such secret: ($p)"}
    }
    ^age -d ...(id-args) $p
}

# Decrypt -> $EDITOR -> re-encrypt. Creates the secret if missing (= add).
# Shared secrets (symlinks into common/) are resolved to the real file so the
# edit updates every consumer.
def "main edit" [host: string, name: string] {
    check-host $host
    check-name $name
    let p = (secret-path $host $name)
    let exists = ($p | path exists)
    let plain = (^mktemp -t "agevault-plain.XXXXXX" | str trim)
    try {
        if $exists { ^age -d ...(id-args) -o $plain $p }
        let editor = ($env.EDITOR? | default "vi" | split row --regex '\s+')
        ^($editor | first) ...($editor | skip 1) $plain
        let target = if $exists {
            $p | path expand
        } else {
            mkdir ($p | path dirname)
            $p
        }
        let enc = (^mktemp -t "agevault-enc.XXXXXX" | str trim)
        ^age -R (recipients-file) -o $enc $plain
        ^chmod 600 $enc
        mv -f $enc $target
    } catch {|e|
        rm -f $plain
        error make {msg: $"edit failed: ($e.msg)"}
    }
    rm -f $plain
    main generate-toml
}

# Encrypt a plaintext secret into the store from stdin (`-`, the default) or a
# file. Non-interactive counterpart to `edit` -- pipe a value straight in, e.g.
# migrating an existing credential:
#   ssh host 'sudo systemd-creds decrypt --name=x /path -' | agevault write h x -
# age reads the source directly (byte-exact; no editor temp file). Shared
# secrets (symlinks into common/) resolve to the real file.
def "main write" [
    host: string
    name: string
    source: string = "-" # `-` = stdin (default), or a path to a plaintext file
] {
    check-host $host
    check-name $name
    let p = (secret-path $host $name)
    let target = if ($p | path exists) {
        $p | path expand
    } else {
        mkdir ($p | path dirname)
        $p
    }
    let enc = (^mktemp -t "agevault-write.XXXXXX" | str trim)
    let res = (do { ^age -R (recipients-file) -o $enc $source } | complete)
    if $res.exit_code != 0 {
        rm -f $enc
        error make {msg: $"encrypt of ($host)/($name) failed: ($res.stderr | str trim)"}
    }
    ^chmod 600 $enc
    mv -f $enc $target
    print $"wrote ($host)/($name)"
    main generate-toml
}

# Delete a secret.
def "main rm" [host: string, name: string] {
    check-host $host
    check-name $name
    let p = (secret-path $host $name)
    if not ($p | path exists) {
        error make {msg: $"no such secret: ($p)"}
    }
    rm -f $p
    print $"removed ($host)/($name)"
    main generate-toml
}

# The receiver, cached on the target under a content-hashed name. Reads the
# plaintext on stdin, compares it byte-for-byte against the currently stored
# value, and only re-encrypts when it actually changed -- echoing "unchanged" or
# "updated". systemd-creds ciphertext is non-deterministic and TPM-bound, so the
# change check MUST decrypt+compare on the target (the pusher can't read the
# target's blob). Args: $1 = credential name, $2 = credstore dir. Plaintext
# buffers live in /dev/shm at umask 077 (root-only) and are trap-cleaned.
def receiver-script [] {
    r##'#!/bin/sh
set -eu
name="$1"; dir="$2"; blob="$dir/$name"
umask 077
tmp="$(mktemp -p /dev/shm agevault.XXXXXX)"; old="$tmp.old"
trap 'rm -f "$tmp" "$old"' EXIT INT TERM
cat > "$tmp"
if [ -f "$blob" ] && systemd-creds decrypt --name="$name" "$blob" - > "$old" 2>/dev/null && cmp -s "$tmp" "$old"; then
  echo unchanged
  exit 0
fi
install -d -m 0700 "$dir"
systemd-creds encrypt --name="$name" - "$dir/.$name.tmp" < "$tmp"
chmod 0400 "$dir/.$name.tmp"
mv -f "$dir/.$name.tmp" "$blob"
echo updated
'##
}

# Cache path is content-addressed: a changed receiver gets a new path, so an old
# cached copy is never reused. Root-only dir (/tmp is world-writable -> a local
# user could plant a script we then exec as root).
def receiver-path [] {
    $"/run/agevault/receive-(receiver-script | hash sha256 | str substring 0..12).sh"
}

# The credstore + systemd-creds need root; a non-root login wraps the command in
# sudo -n (stdin still passes through). The inner command must contain no single
# quotes (the sudo wrap single-quotes it).
def as-root [dest: string, inner: string] {
    if ($dest | str starts-with "root@") {
        $inner
    } else {
        $"sudo -n sh -c '($inner)'"
    }
}

# Decrypt locally (one YubiKey touch, into RAM) and hand the plaintext to the
# cached receiver on the target, which reports whether the value changed.
def push-one [host: string, name: string] {
    check-host $host
    check-name $name
    let p = (secret-path $host $name)
    if not ($p | path exists) {
        error make {msg: $"no such secret: ($p)"}
    }
    let dest = (ssh-dest $host)
    let dir = (credstore-dir)
    let rpath = (receiver-path)
    # Optimistically run the cached receiver; if it is absent it prints a
    # sentinel and exits 97, so we copy it over (once) and retry.
    let run = (as-root $dest $"test -f ($rpath) || { echo AGEVAULT_NO_RECEIVER >&2; exit 97; }; exec sh ($rpath) ($name) ($dir)")

    # Decrypt once into RAM: byte-exact, one touch, readable only by us + root.
    let plain = (^mktemp -p /dev/shm agevault-push.XXXXXX | str trim)
    ^chmod 600 $plain
    let verdict = try {
        let dec = (do { ^age -d ...(id-args) -o $plain $p } | complete)
        if $dec.exit_code != 0 {
            error make {msg: $"decrypt of ($p) failed: ($dec.stderr | str trim)"}
        }
        let r1 = (do { ^cat $plain | ^ssh -o BatchMode=yes $dest $run } | complete)
        let r = if $r1.exit_code == 97 {
            # Cache the receiver in the root-only dir, then retry the delivery.
            let copy = (as-root $dest $"install -d -m 0700 /run/agevault; umask 077; cat > ($rpath); chmod 0700 ($rpath)")
            let cp = (do { receiver-script | ^ssh -o BatchMode=yes $dest $copy } | complete)
            if $cp.exit_code != 0 {
                error make {msg: $"installing receiver on ($host) failed: ($cp.stderr | str trim)"}
            }
            do { ^cat $plain | ^ssh -o BatchMode=yes $dest $run } | complete
        } else {
            $r1
        }
        if $r.exit_code != 0 {
            error make {msg: $"push of ($name) to ($host) failed: ($r.stderr | str trim)"}
        }
        $r.stdout | str trim
    } catch {|e|
        rm -f $plain
        error make {msg: $e.msg}
    }
    rm -f $plain
    print $"($name) -> ($host): ($verdict)"
}

# Deliver secrets: one (host name), a whole host, or the entire fleet.
def "main push" [host?: string, name?: string] {
    if ($host | is-empty) {
        for h in (list-hosts) { for n in (host-secret-names $h) { push-one $h $n } }
    } else if ($name | is-empty) {
        check-host $host
        for n in (host-secret-names $host) { push-one $host $n }
    } else {
        push-one $host $name
    }
}

# Re-encrypt every secret to the current recipients.txt (after rotating a key).
# Dedupes symlinks by real path so a shared secret is rewritten once.
def "main rekey" [] {
    let reals = (all-age-files | each {|f| $f | path expand} | uniq)
    for r in $reals {
        let enc = (^mktemp -t "agevault-rekey.XXXXXX" | str trim)
        # Plaintext stays in the pipe between decrypt and re-encrypt.
        let res = (do { ^age -d ...(id-args) $r | ^age -R (recipients-file) -o $enc } | complete)
        if $res.exit_code != 0 {
            rm -f $enc
            error make {msg: $"rekey failed for ($r): ($res.stderr | str trim)"}
        }
        ^chmod 600 $enc
        mv -f $enc $r
    }
    print $"rekeyed ($reals | length) secret\(s)"
}

# Write the names-only TOML manifest the flake asserts against. Runs
# automatically after edit/rm; also runnable by hand.
def "main generate-toml" [] {
    let dest = (manifest-path)
    let table = (
        list-hosts
        | reduce --fold {} {|h, acc| $acc | insert $h (host-secret-names $h) }
    )
    let text = $"# Generated by 'agevault generate-toml'. Credential names only -- safe to commit.(char newline)(char newline)($table | to toml)"
    mkdir ($dest | path dirname)
    $text | save -f $dest
    print $"wrote manifest: ($dest)"
}

# Completion backend for the shell stubs shipped in share/. Given the words
# already typed after `agevault` (the current partial word excluded), print the
# candidates for the next word, one per line as `value` or
# `value<TAB>description`. A lone `%files` line asks the shell to also offer
# filename completion. Shells filter by the current prefix themselves; the same
# list-hosts / host-secret-names helpers back the real commands, so there is one
# source of truth.
def "main __complete" [...words: string] {
    let n = ($words | length)

    if $n == 0 {
        [
            "cat\tdecrypt a secret to stdout"
            "write\tencrypt a secret from stdin (-) or a file"
            "edit\tdecrypt into $EDITOR then re-encrypt (creates if missing)"
            "rm\tdelete a secret"
            "push\tdeliver secret(s) into hosts' credstore over ssh"
            "rekey\tre-encrypt every secret to recipients.txt"
            "generate-toml\twrite the names-only TOML manifest"
        ] | str join (char newline) | print
        return
    }

    let sub = ($words | first)
    if $sub not-in ["cat" "edit" "rm" "write" "push"] { return }

    if $n == 1 {
        let hosts = (list-hosts)
        if ($hosts | is-not-empty) { $hosts | str join (char newline) | print }
    } else if $n == 2 {
        let names = (host-secret-names ($words | get 1))
        if ($names | is-not-empty) { $names | str join (char newline) | print }
    } else if $n == 3 and $sub == "write" {
        ["-\tread the secret from stdin" "%files"] | str join (char newline) | print
    }
}

def main [] {
    print "agevault - age-backed secret manager for the fleet"
    print ""
    print "Run inside the offline secrets repo. Usage:"
    print "  agevault cat   <host> <name>          decrypt a secret to stdout"
    print "  agevault write <host> <name> [-|file] encrypt from stdin (-) or a file"
    print "  agevault edit  <host> <name>          decrypt -> \$EDITOR -> re-encrypt (creates if missing)"
    print "  agevault rm   <host> <name>     delete a secret"
    print "  agevault push [host] [name]     deliver secret(s) into hosts' credstore over ssh"
    print "  agevault rekey                  re-encrypt everything to recipients.txt"
    print "  agevault generate-toml          write the names-only TOML manifest"
}
