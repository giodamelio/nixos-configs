#!/usr/bin/env nu

def steppath [] {
    $env.STEPPATH? | default "/var/lib/ssh-step-ca"
}

def public-dir [] {
    $env.SSH_CA_PUBLIC_DIR? | default "/var/lib/ssh-ca"
}

# Extra args for systemd-creds, e.g. "--with-key=auto" for TPM-less testing.
def creds-args [] {
    $env.SSH_CA_CREDS_ARGS? | default "" | split row " " | where ($it | is-not-empty)
}

def password-file [] {
    let override = $env.SSH_CA_PASSWORD_FILE?
    if $override != null {
        $override
    } else {
        let dir = $env.CREDENTIALS_DIRECTORY?
        if $dir == null {
            error make {msg: "no CA password: set SSH_CA_PASSWORD_FILE or run with the ssh-ca-password credential"}
        }
        $dir | path join "ssh-ca-password"
    }
}

def cert-path [kind: string, name: string] {
    let base = (public-dir) | path join "certs"
    if $kind == "client" {
        $base | path join "clients" $"($name)-cert.pub"
    } else {
        $base | path join $"($name)-cert.pub"
    }
}

def parse-cert [cert: path] {
    let text = (^ssh-keygen -Lf $cert | lines)
    let fp = ($text | parse -r 'Public key: \S+ SHA256:(?<fp>\S+)' | get 0?.fp)
    let ca_fp = ($text | parse -r 'Signing CA: \S+ SHA256:(?<fp>\S+)' | get 0?.fp)
    let serial = ($text | parse -r 'Serial: (?<serial>\d+)' | get 0?.serial)
    let valid_to = ($text | parse -r 'Valid: from \S+ to (?<to>\S+)' | get 0?.to)
    # Principals = the indented lines between "Principals:" and the next
    # "Key: value" section header.
    let start = ($text | enumerate | where ($it.item | str trim) == "Principals:" | get 0?.index)
    let principals = if $start == null {
        []
    } else {
        $text
        | skip ($start + 1)
        | take while {|l| not ($l | str trim | str contains ":") }
        | each {|l| $l | str trim }
        | where ($it | is-not-empty)
    }
    {fp: $fp, ca_fp: $ca_fp, principals: $principals, serial: $serial, valid_to: $valid_to}
}

def pubkey-fp [pubkey: string, workdir: path] {
    let tmp = ($workdir | path join "fp-probe.pub")
    $pubkey + "\n" | save -f $tmp
    let fp = (^ssh-keygen -lf $tmp | parse -r 'SHA256:(?<fp>\S+)' | get 0?.fp)
    rm $tmp
    $fp
}

# One-time CA creation (the systemd unit also gates on ca.json existing).
def "main init" [] {
    let sp = (steppath)
    if ($sp | path join "config" "ca.json" | path exists) {
        print $"ssh-ca already initialized at ($sp)"
        return
    }

    let workdir = (^mktemp -d | str trim)
    let pw = ($workdir | path join "password")
    ^openssl rand -base64 32 o> $pw
    ^chmod 600 $pw

    mkdir $sp
    ^chmod 700 $sp
    $env.STEPPATH = $sp
    (^step ca init --ssh
        --name "gio.ninja SSH CA"
        --dns ca-ssh.gio.ninja
        --address "127.0.0.1:8444"
        --provisioner admin
        --password-file $pw
        --provisioner-password-file $pw
        --deployment-type standalone)

    # Allow 1-year certs (provisioner default max is 720h). `+=` preserves
    # enableSSHCA — replacing claims wholesale kills SSH signing.
    let cfg = ($sp | path join "config" "ca.json")
    (^jq '.authority.provisioners[0].claims += {
        "maxHostSSHCertDuration": "8784h", "defaultHostSSHCertDuration": "8760h",
        "maxUserSSHCertDuration": "8784h", "defaultUserSSHCertDuration": "720h"
    }' $cfg) | save -f $"($cfg).new"
    mv -f $"($cfg).new" $cfg

    mkdir /usr/lib/credstore.encrypted
    ^systemd-creds encrypt ...(creds-args) --name=ssh-ca-password $pw /usr/lib/credstore.encrypted/ssh-ca-password

    let pub = (public-dir)
    mkdir $pub
    cp ($sp | path join "certs" "ssh_host_ca_key.pub") ($pub | path join "host-ca.pub")
    cp ($sp | path join "certs" "ssh_user_ca_key.pub") ($pub | path join "user-ca.pub")
    ^chmod 644 ($pub | path join "host-ca.pub") ($pub | path join "user-ca.pub")

    rm -rf $workdir

    print ""
    print "SSH CA initialized. Paste these into modules/aspects/ssh/data/:"
    print $"  host-ca.pub: (open ($pub | path join 'host-ca.pub') | str trim)"
    print $"  user-ca.pub: (open ($pub | path join 'user-ca.pub') | str trim)"
}

# Targets JSON: { "hosts":   { "<name>": { "pubkey", "principals" } },
#                 "clients": { "<name>": { "pubkey", "principals" } } }
def "main sign" [
    targets: path # JSON file declaring hosts/clients to sign
] {
    let sp = (steppath)
    if not ($sp | path join "config" "ca.json" | path exists) {
        error make {msg: $"ssh-ca not initialized: ($sp)/config/ca.json missing (run ssh-ca init)"}
    }
    $env.STEPPATH = $sp
    let pw = (password-file)
    if not ($pw | path exists) {
        error make {msg: $"CA password file not found: ($pw)"}
    }

    let spec = (open $targets)
    let workdir = (^mktemp -d | str trim)
    mkdir ((public-dir) | path join "certs" "clients")

    # Certs signed by an older CA (re-key) must never count as fresh.
    let ca_fps = {
        host: (^ssh-keygen -lf ($sp | path join "certs" "ssh_host_ca_key.pub") | parse -r 'SHA256:(?<fp>\S+)' | get 0.fp)
        client: (^ssh-keygen -lf ($sp | path join "certs" "ssh_user_ca_key.pub") | parse -r 'SHA256:(?<fp>\S+)' | get 0.fp)
    }

    let entries = [
        ...($spec.hosts? | default {} | transpose name target | insert kind "host")
        ...($spec.clients? | default {} | transpose name target | insert kind "client")
    ]

    let results = ($entries | each {|e|
        let cert = (cert-path $e.kind $e.name)
        let want_fp = (pubkey-fp $e.target.pubkey $workdir)

        let current = if ($cert | path exists) { parse-cert $cert } else { null }
        let fresh = if $current == null {
            false
        } else {
            let key_ok = ($current.fp == $want_fp)
            let ca_ok = ($current.ca_fp == ($ca_fps | get $e.kind))
            let principals_ok = (($current.principals | sort) == ($e.target.principals | sort))
            let validity_ok = ((($current.valid_to | into datetime) - (date now)) > 90day)
            $key_ok and $ca_ok and $principals_ok and $validity_ok
        }

        if $fresh {
            {name: $e.name, kind: $e.kind, status: "ok", valid_to: $current.valid_to, serial: $current.serial}
        } else {
            let keyfile = ($workdir | path join $"($e.name).pub")
            $e.target.pubkey + "\n" | save -f $keyfile
            mut args = [
                ssh certificate --sign --offline
                --not-after 8760h
                --provisioner admin
                --provisioner-password-file $pw
                --password-file $pw
            ]
            if $e.kind == "host" {
                $args = ($args | append "--host")
            }
            for p in $e.target.principals {
                $args = ($args | append ["--principal" $p])
            }
            ^step ...$args $e.name $keyfile
            let signed = ($workdir | path join $"($e.name)-cert.pub")
            ^chmod 644 $signed
            mv -f $signed $cert
            let info = (parse-cert $cert)
            {name: $e.name, kind: $e.kind, status: "signed", valid_to: $info.valid_to, serial: $info.serial}
        }
    })

    rm -rf $workdir

    print ($results | table)
    let signed = ($results | where status == "signed")
    if ($signed | length) > 0 {
        print ""
        print $"(($signed | length)) certificate\(s\) \(re\)signed — copy (public-dir)/certs/ into modules/aspects/ssh/data/certs/ and deploy."
    }
}

def sync-file [src: path, dest: path] {
    if not ($src | path exists) {
        return null
    }
    let changed = if ($dest | path exists) {
        (open --raw $src) != (open --raw $dest)
    } else {
        true
    }
    if $changed {
        cp $src $dest
    }
    {file: ($dest | path basename), status: (if $changed { "updated" } else { "unchanged" })}
}

def "main sync" [
    --repo: string = "~/nixos-configs" # config repo checkout
] {
    let repo = ($repo | path expand)
    if not ($repo | path join "flake.nix" | path exists) {
        error make {msg: $"($repo) does not look like the config repo \(no flake.nix\) — pass --repo"}
    }
    let data = ($repo | path join "modules" "aspects" "ssh" "data")
    mkdir ($data | path join "certs" "clients")

    let unit_state = (do { ^systemctl show -p LoadState --value ssh-ca-sign.service } | complete)
    if $unit_state.exit_code == 0 and ($unit_state.stdout | str trim) == "loaded" {
        if (^id -u | str trim) == "0" {
            ^systemctl start ssh-ca-init.service
            ^systemctl start ssh-ca-sign.service
        } else {
            ^sudo systemctl start ssh-ca-init.service
            ^sudo systemctl start ssh-ca-sign.service
        }
    } else {
        print "note: ssh-ca units not found; copying already-generated artifacts only"
    }

    let pub = (public-dir)
    let results = ([
        (sync-file ($pub | path join "host-ca.pub") ($data | path join "host-ca.pub"))
        (sync-file ($pub | path join "user-ca.pub") ($data | path join "user-ca.pub"))
        ...(glob ($pub | path join "certs" "*-cert.pub") | each {|src|
            sync-file $src ($data | path join "certs" ($src | path basename))
        })
        ...(glob ($pub | path join "certs" "clients" "*-cert.pub") | each {|src|
            sync-file $src ($data | path join "certs" "clients" ($src | path basename))
        })
    ] | where ($it != null))

    print ($results | table)
    let updated = ($results | where status == "updated" | length)
    if $updated > 0 {
        print ""
        print $"($updated) file\(s\) updated in ($data) — commit and deploy."
    } else {
        print "repo already in sync."
    }
}

def main [] {
    print "ssh-ca - file-based SSH certificate authority (step-managed, no daemon)"
    print ""
    print "Usage:"
    print "  ssh-ca init             one-time CA creation (root)"
    print "  ssh-ca sign <targets>   sign/renew certs from a targets JSON (root)"
    print "  ssh-ca sync [--repo …]  init+sign via systemd, copy artifacts into the repo"
}
