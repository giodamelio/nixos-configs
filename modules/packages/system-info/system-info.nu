# inxi keys look like "001#1#1#ID": the leading number is the display order
def clean-record []: record -> record {
    transpose key value
    | sort-by key
    | update key { split row '#' | last }
    | transpose -rd
}

def fill-missing []: list<record> -> list<record> {
    let rows = $in
    let cols = ($rows | each { columns } | flatten | uniq)
    $rows | each {|row|
        $cols | reduce --fold {} {|col, acc| $acc | insert $col ($row | get -o $col | default "") }
    }
}

def section-name [key: string]: nothing -> string {
    $key | split row '#' | last
}

def width []: nothing -> int {
    if (is-terminal --stdout) { (term size).columns } else { $env.COLUMNS? | default 120 | into int }
}

def heading [title: string]: nothing -> string {
    let prefix = $"━━┫ ($title) ┣"
    let rest = ((width) - ($prefix | str length --grapheme-clusters))
    $"(ansi cyan_bold)($prefix)('' | fill --character '━' --width $rest)(ansi reset)"
}

def subheading [title: string]: nothing -> string {
    $"(ansi green_bold)($title)(ansi reset)"
}

def note [text: string]: nothing -> string {
    $"(ansi default_dimmed)($text)(ansi reset)"
}

def unmounted-partitions []: nothing -> list<record> {
    let devices = (
        lsblk --json --list --output NAME,PKNAME,TYPE,PATH,SIZE,FSTYPE,LABEL,PARTTYPENAME,PARTLABEL,UUID,MOUNTPOINTS
        | from json
        | get blockdevices
    )
    # partitions holding a LUKS/LVM child are in use even without a mountpoint of their own
    let parents = ($devices | get pkname | compact)

    $devices
    | where type == "part" and ($it.mountpoints | compact | is-empty) and $it.name not-in $parents
    | select path size fstype label parttypename partlabel uuid
}

# Overview of mounts, physical disks, partitions and unmounted partitions
def "main disks" [] {
    print (heading "Mounts")
    # duf only uses truecolor and usage bars when it writes straight to a terminal
    ^duf

    let tmp = (mktemp --tmpdir --suffix .json disks.XXXXXX)
    inxi --tty -xxx --disk-full --partitions-full --output json --output-file $tmp | ignore
    let sections = (open --raw $tmp | from json)
    rm $tmp

    let disks = ($sections | each {|section|
        let key = ($section | columns | first)
        let rows = ($section | get $key | each { clean-record })
        let devices = ($rows | where ($it | get -o ID) != null)
        let notes = ($rows | where ($it | get -o ID) == null)

        [
            (subheading (section-name $key))
            ...($notes | each { transpose k v | where v != "" | each { $"(ansi default_dimmed)($in.k):(ansi reset) ($in.v)" } | str join "  " })
            ($devices | fill-missing | table --index false)
        ]
    } | flatten)

    let unmounted = (unmounted-partitions)

    [
        (heading "Disks")
        ...$disks
        (subheading "Unmounted")
        (if ($unmounted | is-empty) { note "No unmounted partitions." } else { $unmounted | table --index false })
    ] | str join "\n" | print $in
}

# ss endpoints look like 0.0.0.0:22, [::]:22, 127.0.0.53%lo:53 or [fe80::1%eth0]:123
def parse-endpoint [endpoint: string]: nothing -> record {
    $endpoint | parse --regex '^\[?(?<address>.*?)(?:%[^\]]*)?\]?:(?<port>[^:]+)$' | first
}

def systemd-unit [pid: int]: nothing -> string {
    let path = $"/proc/($pid)/cgroup"
    # the process can exit between ss listing it and us reading /proc
    if not ($path | path exists) { return "" }
    open --raw $path | lines | first | split row '/' | last
}

# ss reports the kernel comm, which is cut to 15 chars, so read the full argv[0] instead
def process-name [pid: int, comm: string]: nothing -> string {
    let path = $"/proc/($pid)/cmdline"
    if not ($path | path exists) { return $comm }
    let argv0 = (open --raw $path | split row (char nul) | first)
    if ($argv0 | is-empty) { return $comm }
    $argv0 | path basename | str replace --regex '^\.(.*)-wrapped$' '$1'
}

# Looks up each uid individually because enumerating passwd skips systemd DynamicUser accounts
def user-names [uids: list<int>]: nothing -> record {
    if ($uids | is-empty) { return {} }
    # exits 2 when some uids have no entry; those stay numeric
    ^getent passwd ...($uids | each { into string }) | complete | get stdout
    | lines
    | split column ':' name password uid
    | reduce --fold {} {|user, acc| $acc | insert $user.uid $user.name }
}

# UDP has no listen state, so ss lists every bound socket; empty means nothing marks it as a non-server
def udp-client-reason [socket: record, ephemeral: list<int>, shared: list<int>]: nothing -> string {
    if ($socket.address =~ '^(22[4-9]|23\d)\.' or ($socket.address | str starts-with "ff")) { return "multicast address" }
    # several processes on one UDP port means SO_REUSEPORT multicast listeners like mDNS
    if $socket.port in $shared { return "shared by several processes" }
    if $socket.port >= $ephemeral.0 and $socket.port <= $ephemeral.1 { return "ephemeral port" }
    ""
}

# Listening TCP/UDP ports with their process and systemd unit (sudo fills in other users' processes)
def "main ports" [] {
    let procs = (ps --long | select pid user_id)

    let sockets = (
        ^ss --tcp --udp --listening --numeric --processes --no-header
        | lines
        | each {|line|
            let fields = ($line | split row --regex '\s+')
            let local = (parse-endpoint ($fields | get 4))
            let owners = ($fields | skip 6 | str join ' ' | parse --regex '\("(?<name>[^"]+)",pid=(?<pid>\d+)')
            let pid = ($owners | get -o 0.pid | if $in == null { null } else { into int })
            let process = (if $pid == null { null } else { $procs | where pid == $pid | get -o 0 })
            let uid = ($process | get -o user_id)
            let loopback = ($local.address | str starts-with "127.") or $local.address == "::1"

            {
                proto: ($fields | first)
                port: ($local.port | into int)
                address: $local.address
                exposure: (if $loopback { "local" } else { $"(ansi yellow_bold)exposed(ansi reset)" })
                process: ($owners | each { process-name ($in.pid | into int) $in.name } | uniq | str join ", ")
                pid: ($pid | default "")
                user: $uid
                unit: (if $pid == null { "" } else { systemd-unit $pid })
            }
        }
        | uniq
        # lowest ports end up at the bottom, right above the prompt
        | sort-by --reverse port proto address
    )
    let names = (user-names ($sockets | get user | compact | uniq))
    let sockets = ($sockets | update user {|row|
        if $row.user == null { "" } else { $names | get -o ($row.user | into string) | default ($row.user | into string) }
    })

    let ephemeral = (open --raw /proc/sys/net/ipv4/ip_local_port_range | split row --regex '\s+' | first 2 | into int)
    let udp = ($sockets | where proto == "udp" | reject proto)
    let shared = (
        $udp
        | where pid != ""
        | group-by --to-table port
        | where ($it.items | get pid | uniq | length) > 1
        | get port
        | into int
    )
    let udp = ($udp | insert reason {|row| udp-client-reason $row $ephemeral $shared } | move reason --after port)
    let tcp = ($sockets | where proto == "tcp" | reject proto)
    let hidden = (not (is-admin) and ($sockets | any { $in.process == "" }))

    # servers go last so they sit right above the prompt
    [
        (subheading "UDP clients and multicast listeners")
        ($udp | where reason != "" | table --index false)
        (subheading "UDP servers")
        ($udp | where reason == "" | reject reason | table --index false)
        (subheading "TCP servers")
        ($tcp | table --index false)
        ...(if $hidden { [(note "Some processes are hidden; run with sudo to see sockets owned by other users.")] } else { [] })
    ] | str join "\n" | print $in
}

def link-state [link: record]: nothing -> string {
    if "UP" not-in $link.flags { return $"(ansi red)down(ansi reset)" }
    if "LOWER_UP" not-in $link.flags { return $"(ansi yellow)no carrier(ansi reset)" }
    $"(ansi green)up(ansi reset)"
}

# Wired speed in Mb/s; the kernel errors on reads for down or virtual links, which just means unknown
def link-speed [name: string]: nothing -> string {
    let read = (^cat $"/sys/class/net/($name)/speed" | complete)
    if $read.exit_code != 0 { return "" }
    let mbits = ($read.stdout | str trim | into int)
    if $mbits <= 0 { return "" }
    if $mbits >= 1000 { $"($mbits / 1000) Gb/s" } else { $"($mbits) Mb/s" }
}

def wireless-interfaces []: nothing -> list<string> {
    ^iw dev | parse --regex '\s+Interface (?<name>\S+)' | get name
}

def wifi-link [name: string]: nothing -> record {
    let fields = (
        ^iw dev $name link
        | lines
        | str trim
        | parse "{key}: {value}"
        | reduce --fold {} {|field, acc| $acc | upsert $field.key $field.value }
    )
    {
        ssid: ($fields | get -o SSID | default "")
        signal: ($fields | get -o signal | default "")
        bitrate: ($fields | get -o "tx bitrate" | default "" | split row ' ' | first 2 | str join ' ')
    }
}

def address-lifetime [address: record]: nothing -> string {
    # 4294967295 is the kernel's "forever"
    if $address.valid_life_time == 4294967295 { return "" }
    $address.valid_life_time // 60 * 1min | into string
}

def dns-servers []: nothing -> record {
    let result = (^resolvectl dns | complete)
    if $result.exit_code != 0 {
        return {servers: [], error: $"resolvectl dns failed: ($result.stderr | str trim)"}
    }
    let servers = (
        $result.stdout
        | lines
        | parse --regex '^(?<scope>[^:]+):\s*(?<servers>.*)$'
        | where servers != ""
    )
    {servers: $servers, error: null}
}

def ip [text: string]: nothing -> string {
    $"(ansi white_bold)($text)(ansi reset)"
}

def dim [text: string]: nothing -> string {
    $"(ansi default_dimmed)($text)(ansi reset)"
}

# "label value" pairs on one line, skipping empty values
def fields [pairs: list<list<any>>]: nothing -> string {
    $pairs
    | where ($it.1 != null and $it.1 != "")
    | each { $"(dim $in.0) ($in.1)" }
    | str join "  "
}

# Pads each column to its widest cell so rows line up
def align [rows: list<list<string>>]: nothing -> list<string> {
    if ($rows | is-empty) { return [] }
    let widths = (0..<($rows | first | length) | each {|i| $rows | each { $in | get $i | into string | ansi strip | str length } | math max })
    $rows | each {|row|
        $row | enumerate | each {|cell|
            let padding = ($widths | get $cell.index) - ($cell.item | into string | ansi strip | str length)
            $"($cell.item)('' | fill --width $padding)"
        } | str join "  " | str trim --right
    }
}

def interface-lines [link: record, wireless: list<string>, dns: list<record>]: nothing -> list<string> {
    let wifi = (if $link.ifname in $wireless { wifi-link $link.ifname } else { null })
    let errors = ($link.stats64.rx.errors + $link.stats64.tx.errors)
    let dropped = ($link.stats64.rx.dropped + $link.stats64.tx.dropped)
    let kind = (if $wifi != null { "wifi" } else { $link | get -o linkinfo.info_kind | default $link.link_type })
    let speed = (if $wifi == null { link-speed $link.ifname } else { $wifi.bitrate })

    let addresses = ($link.addr_info | each {|address|
        [
            (if $address.family == "inet" { "IPv4" } else { "IPv6" })
            $"(ip $address.local)/($address.prefixlen)"
            $address.scope
            ([
                (if ($address | get -o dynamic | default false) { "dynamic" } else { "static" })
                (if ($address | get -o temporary | default false) { "temporary" })
            ] | compact | str join ", ")
            (address-lifetime $address | if $in == "" { "" } else { dim $in })
        ]
    })

    [
        $"(ansi magenta_bold)($link.ifname)(ansi reset)  (link-state $link)  ([$kind $speed] | where $it != '' | str join '  ')"
        $"  (fields [
            [ssid (if $wifi == null or $wifi.ssid == '' { null } else { $'($wifi.ssid) \(($wifi.signal)\)' })]
            [mac ($link | get -o address)]
            [mtu $link.mtu]
            [rx ($link.stats64.rx.bytes | into filesize)]
            [tx ($link.stats64.tx.bytes | into filesize)]
            [errors (if $errors > 0 { $'(ansi red)($errors)(ansi reset)' })]
            [dropped (if $dropped > 0 { $'(ansi yellow)($dropped)(ansi reset)' })]
            [dns ($dns | where ($it.scope | str ends-with $'\(($link.ifname)\)') | get -o 0.servers)]
        ])"
        ...(align $addresses | each { $"  ($in)" })
        ""
    ]
}

# Interfaces with their link details and addresses, then default routes and DNS servers
def "main network" [] {
    let wireless = (wireless-interfaces)
    let dns = (dns-servers)
    let links = (^ip --json --details --stats addr | from json)

    let routes = (
        [(^ip --json -4 route show default | from json) (^ip --json -6 route show default | from json)]
        | flatten
        | each {|route|
            [
                ($route | get -o gateway | if $in == null { "direct" } else { ip $in })
                $"(dim 'via') ($route | get -o dev | default '')"
                (dim ($route | get -o protocol | default ""))
                (dim $"metric ($route | get -o metric | default 0)")
            ]
        }
    )

    let dns_lines = (
        if $dns.error != null {
            [(note $dns.error)]
        } else if ($dns.servers | is-empty) {
            [(note "No DNS servers.")]
        } else {
            # "Link 3 (enp0s31f6)" reads better as just the interface name
            align ($dns.servers | each {|entry|
                [(dim ($entry.scope | str replace --regex '^Link \d+ \((.*)\)$' '$1')) ($entry.servers | split row ' ' | each { ip $in } | str join ' ')]
            })
        }
    )

    [
        (subheading "Interfaces")
        ...($links | each { interface-lines $in $wireless $dns.servers } | flatten | each { if $in == "" { "" } else { $"  ($in)" } })
        (subheading "Default routes")
        ...(if ($routes | is-empty) { [(note "No default routes.")] } else { align $routes | each { $"  ($in)" } })
        ""
        (subheading "DNS servers")
        ...($dns_lines | each { $"  ($in)" })
    ] | str join "\n" | print $in
}

def indent []: list<string> -> list<string> {
    each { if $in == "" { "" } else { $"  ($in)" } }
}

def section [title: string, lines: list<string>, empty: string]: nothing -> list<string> {
    [
        (subheading $title)
        ...(if ($lines | is-empty) { [(note $empty)] } else { $lines } | indent)
        ""
    ]
}

def finish []: list<string> -> nothing {
    print ($in | str join "\n" | str trim --right)
}

def plural [count: int, noun: string]: nothing -> string {
    if $count == 1 { $"($count) ($noun)" } else { $"($count) ($noun)s" }
}

def usec-ago [usec: int]: nothing -> string {
    if $usec == 0 { return "never" }
    $usec * 1000 | into datetime | date humanize
}

# One `systemctl show` call covers every unit; its blocks are separated by blank lines
def unit-properties [scope: list<string>, units: list<string>]: nothing -> list<record> {
    if ($units | is-empty) { return [] }
    ^systemctl ...$scope show --property=Id,ActiveEnterTimestampMonotonic,MemoryCurrent,NRestarts ...$units
    | split row "\n\n"
    | where ($it | str trim) != ""
    | each { lines | parse "{key}={value}" | transpose -rd }
}

def service-rows [scope: list<string>]: nothing -> list<list<string>> {
    let uptime = (open --raw /proc/uptime | split row ' ' | first | into float)
    let units = (^systemctl ...$scope list-units --type=service --state=running --output=json | from json | get unit)

    unit-properties $scope $units
    | sort-by Id
    | each {|unit|
        let running = ($uptime - ($unit.ActiveEnterTimestampMonotonic | into float) / 1_000_000)
        let restarts = ($unit.NRestarts | into int)
        [
            $unit.Id
            (dim $"up (($running // 60 | into int) * 1min)")
            # unlimited or unaccounted memory reads as "[not set]"
            (if $unit.MemoryCurrent =~ '^\d+$' { $unit.MemoryCurrent | into int | into filesize | into string } else { "" })
            (if $restarts > 0 { $"(ansi yellow)(plural $restarts restart)(ansi reset)" } else { "" })
        ]
    }
}

# root has no user bus of its own, so under sudo look at the invoking user's session instead
def user-scope []: nothing -> any {
    if not (is-admin) { return {name: "user", flags: ["--user"]} }
    let user = ($env.SUDO_USER? | default "")
    if $user == "" or $user == "root" { return null }
    {name: "user", flags: ["--user" $"--machine=($user)@.host"]}
}

# Timers, running user and system services, then failed units right above the prompt
def "main services" [] {
    let user = (user-scope)
    let scopes = [{name: "system", flags: []} ...(if $user == null { [] } else { [$user] })]

    let timers = (
        $scopes
        | each {|scope| ^systemctl ...$scope.flags list-timers --all --output=json | from json | insert scope $scope.name }
        | flatten
        | sort-by next
        | each {|timer|
            [
                $timer.unit
                (dim $timer.scope)
                (dim $timer.activates)
                $"(dim 'last') (usec-ago $timer.last)"
                $"(dim 'next') (usec-ago $timer.next)"
            ]
        }
    )

    let failed = (
        $scopes
        | each {|scope|
            ^systemctl ...$scope.flags list-units --failed --output=json
            | from json
            | each {|unit| [$"(ansi red_bold)($unit.unit)(ansi reset)" $scope.name (dim $unit.description)] }
        }
        | flatten
    )

    [
        ...(section "Timers" (align $timers) "No timers.")
        ...(if $user == null {
            section "User services" [] "Running as root without sudo, so there is no user session to show."
        } else {
            section "User services" (align (service-rows $user.flags)) "No running user services."
        })
        ...(section "System services" (align (service-rows [])) "No running services.")
        ...(section "Failed units" (align $failed) "No failed units.")
    ] | finish
}

def pool-health [state: string]: nothing -> string {
    if $state == "ONLINE" { $"(ansi green)($state)(ansi reset)" } else { $"(ansi red_bold)($state)(ansi reset)" }
}

def scrub-status [pool: record]: nothing -> string {
    let scan = ($pool | get -o scan_stats)
    if $scan == null or $scan.function == "NONE" { return $"(ansi yellow)never scrubbed(ansi reset)" }

    let function = ($scan.function | str lowercase)
    if $scan.state == "SCANNING" {
        let percent = (if $scan.to_examine > 0 { $scan.examined * 100 // $scan.to_examine } else { 0 })
        return $"(ansi cyan)($function) running, ($percent)% examined(ansi reset)"
    }

    let finished = ($scan.end_time * 1_000_000_000 | into datetime)
    let errors = (if $scan.errors > 0 { $"(ansi red_bold)($scan.errors) errors(ansi reset)" } else { "0 errors" })
    let when = ($finished | date humanize)
    # a scrub more than a month old is overdue on most schedules
    let when = (if ((date now) - $finished) > 30day { $"(ansi yellow)($when)(ansi reset)" } else { $when })
    $"($function) ($scan.state | str lowercase) ($when), ($errors)"
}

# Every vdev below the root that is not ONLINE or has seen errors
def problem-vdevs [vdev: record]: nothing -> list<list<string>> {
    let children = ($vdev | get -o vdevs | default {} | values)
    let own = (
        if $vdev.vdev_type != "root" and ($vdev.state != "ONLINE" or $vdev.read_errors + $vdev.write_errors + $vdev.checksum_errors > 0) {
            [[
                $vdev.name
                (pool-health $vdev.state)
                (dim $"read ($vdev.read_errors)  write ($vdev.write_errors)  checksum ($vdev.checksum_errors)")
            ]]
        } else { [] }
    )
    [...$own ...($children | each { problem-vdevs $in } | flatten)]
}

def zfs-lines []: nothing -> list<string> {
    if (which zpool | is-empty) { return [(note "zpool is not installed.")] }

    let status = (^zpool status -j -p --json-int | from json | get pools)
    let list = (^zpool list -j --json-int | from json | get pools)

    $status | values | each {|pool|
        let props = ($list | get $pool.name | get properties)
        let problems = (problem-vdevs ($pool.vdevs | get $pool.name))
        [
            $"(ansi magenta_bold)($pool.name)(ansi reset)  (pool-health $pool.state)  (fields [
                [size ($props.size.value | into filesize)]
                [used ($props.allocated.value | into filesize)]
                [free ($props.free.value | into filesize)]
                [capacity $"($props.capacity.value)%"]
                [fragmentation $"($props.fragmentation.value)%"]
            ])"
            $"  (dim 'scrub') (scrub-status $pool)"
            ...(align $problems | each { $"  ($in)" })
        ]
    } | flatten
}

def snapshot-lines []: nothing -> list<string> {
    if (which zfs | is-empty) { return [] }

    let snapshots = (
        ^zfs list -H -p -t snapshot -o name,creation
        | lines
        | parse "{name}\t{creation}"
        | insert dataset { $in.name | split row '@' | first }
    )
    let datasets = (^zfs list -H -o name | lines)

    align ($datasets | each {|dataset|
        let latest = ($snapshots | where dataset == $dataset | last 1 | get -o 0)
        if $latest == null {
            [$dataset (dim "no snapshots") ""]
        } else {
            let count = ($snapshots | where dataset == $dataset | length)
            [
                $dataset
                ($latest.creation | into int | $in * 1_000_000_000 | into datetime | date humanize)
                (dim $"(plural $count snapshot), latest ($latest.name | split row '@' | last)")
            ]
        }
    })
}

def bcachefs-device [path: path]: nothing -> list<string> {
    # state lists every possible state with the active one in brackets
    let state = (open --raw $"($path)/state" | parse --regex '\[(?<state>\w+)\]' | get -o 0.state | default "unknown")
    let errors = (
        open --raw $"($path)/io_errors"
        | lines
        | take until { $in =~ 'since [0-9]' }
        | parse --regex '^\s*(?<kind>\w+):\s*(?<count>\d+)'
        | update count { into int }
    )
    let error_total = ($errors | get count | math sum)

    [
        ($path | path join block | path expand | path basename)
        (open --raw $"($path)/label" | str trim)
        (if $state == "rw" { $"(ansi green)($state)(ansi reset)" } else { $"(ansi yellow)($state)(ansi reset)" })
        (dim $"durability (open --raw $'($path)/durability' | str trim)")
        (if $error_total > 0 {
            $"(ansi red_bold)($errors | each { $'($in.kind) ($in.count)' } | str join '  ')(ansi reset)"
        } else {
            dim "no io errors"
        })
    ]
}

def bcachefs-lines []: nothing -> list<string> {
    if not ("/sys/fs/bcachefs" | path exists) { return [] }

    let mounts = (^findmnt --json --types bcachefs --output SOURCE,TARGET | from json | get filesystems)

    ls /sys/fs/bcachefs | where type == dir | get name | each {|fs|
        let devices = (ls $fs | where name =~ 'dev-\d+$' | get name | each { bcachefs-device $in })
        let names = ($devices | each { $in.0 })
        # the mount source lists member devices, e.g. /dev/sda1:/dev/sdb2[/subvolume]
        let mount = ($mounts | where ($it.source | str replace --regex '\[.*\]$' '' | split row ':' | path basename | any {|dev| $dev in $names }) | get -o 0.target)
        [
            $"(ansi magenta_bold)($fs | path basename)(ansi reset)  (fields [[mounted $mount]])"
            ...(align $devices | each { $"  ($in)" })
        ]
    } | flatten
}

# ZFS pool health and scrubs, bcachefs devices, and the newest snapshot of each dataset
def "main storage" [] {
    [
        ...(section "Snapshots" (snapshot-lines) "No ZFS datasets.")
        ...(section "bcachefs" (bcachefs-lines) "No bcachefs filesystems.")
        ...(section "ZFS pools" (zfs-lines) "No ZFS pools.")
    ] | finish
}

def generation-number [link: string]: nothing -> int {
    $link | path basename | parse "system-{number}-link" | get 0.number | into int
}

# Interesting parts of a system that, if they differ, need a reboot rather than a switch
def boot-parts [system: path]: nothing -> list<string> {
    ["kernel" "initrd" "kernel-modules"] | each { $system | path join $in | path expand }
}

# Current, booted and next-boot generations, whether a reboot is pending, and the store's free space
def "main nix" [] {
    let profiles = "/nix/var/nix/profiles"
    let generations = (
        ls -l $profiles
        | where name =~ 'system-\d+-link$'
        | insert number { generation-number $in.name }
        | sort-by number
    )
    let current = ("/run/current-system" | path expand)
    let booted = ("/run/booted-system" | path expand)
    let next_boot = ($profiles | path join system | path expand)
    let generation_of = {|system| $generations | where target == $system | get -o 0.number }

    let version = (^nixos-version --json | from json)
    let store = (^df --block-size=1 --output=size,used,avail /nix/store | lines | last | split row --regex '\s+' | where $it != "" | into int)

    let status = [
        (if (boot-parts $current) != (boot-parts $booted) {
            $"(ansi red_bold)reboot needed(ansi reset) (dim 'kernel, initrd or modules changed since boot')"
        } else if $current != $booted {
            $"(ansi yellow)switched since boot(ansi reset) (dim 'no kernel change, reboot optional')"
        } else {
            $"(ansi green)running the booted system(ansi reset)"
        })
        (if $next_boot != $current {
            $"(ansi yellow)next boot uses generation (do $generation_of $next_boot), which is not active(ansi reset)"
        })
    ] | compact

    let recent = ($generations | last 5 | each {|generation|
        let markers = [
            (if $generation.target == $current { "current" })
            (if $generation.target == $booted { "booted" })
            (if $generation.target == $next_boot { "next boot" })
        ] | compact
        [
            ($generation.number | into string)
            ($generation.modified | date humanize)
            (dim ($generation.target | path basename | str substring 0..<8))
            (if ($markers | is-empty) { "" } else { $"(ansi cyan)($markers | str join ', ')(ansi reset)" })
        ]
    })

    [
        ...(section "Store" [(fields [
            [size ($store.0 | into filesize)]
            [used ($store.1 | into filesize)]
            [free ($store.2 | into filesize)]
        ])] "")
        ...(section "Generations" (align $recent) "No system generations.")
        ...(section "System" [
            (fields [
                [nixos $version.nixosVersion]
                [nixpkgs ($version.nixpkgsRevision | str substring 0..<12)]
                [kernel $version.kernelVersion]
                [revision ($version | get -o configurationRevision)]
            ])
            $"(fields [
                [current (do $generation_of $current)]
                [booted (do $generation_of $booted)]
                ['next boot' (do $generation_of $next_boot)]
            ])"
            ...$status
        ] "")
    ] | finish
}

def main [] {
    help main
}
