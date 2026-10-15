# Replaced atomically via mv so coredns never reads a partial file; prints
# whether the zone changed.
def remote-install [name: string] {
    let d = "/var/lib/fleet-dns"
    let inner = $"set -e; t=`mktemp -p ($d) .push.XXXXXX`; cat > \"$t\"; if cmp -s \"$t\" ($d)/($name); then rm -f \"$t\"; echo unchanged; else chmod 0644 \"$t\"; mv -f \"$t\" ($d)/($name); echo updated; fi"
    $"sudo -n sh -c '($inner)'"
}

# Push this checkout's zones to every DNS server. coredns picks them up within
# its 10s reload interval.
def "main push" [] {
    let zones = (ls $zones_dir | get name)
    let results = ($servers | each {|s|
        $zones | each {|z|
            let name = ($z | path basename)
            let r = (open --raw $z | ^ssh -o BatchMode=yes $s.dest (remote-install $name) | complete)
            {
                server: $s.name
                zone: $name
                ok: ($r.exit_code == 0)
                result: (if $r.exit_code == 0 { $r.stdout | str trim } else { $r.stderr | str trim })
            }
        }
    } | flatten)

    $results | select server zone result | print
    if ($results | any {|r| not $r.ok }) {
        error make {msg: "fleet-dns: push failed on at least one server (see above)"}
    }
}

def main [] {
    print "fleet-dns - push the fleet DNS zones without a deploy"
    print ""
    print "Run from the nixos-configs checkout:"
    print "  nix run .#fleet-dns -- push    install this checkout's zones on every DNS server"
}
