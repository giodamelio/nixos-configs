# heartbeat-probe — emit influx line protocol for telegraf's exec inputs.
# One subcommand per signal; each prints a single measurement line (or nothing).

# Count of systemd units in the failed state (dead / crash-looping).
def "main failed-units" [] {
  let out = (^systemctl list-units --failed --no-legend --plain | str trim)
  let n = (if ($out | is-empty) { 0 } else { $out | lines | length })
  print $"systemd_health failed_units=($n)i"
}

# zpool state per pool: degraded flag (ONLINE = 0), fill %, fragmentation %.
def "main zpool" [] {
  for p in (^zpool list -j | from json | get pools | values) {
    let cap = (try { $p.properties.capacity.value | str replace "%" "" | into int } catch { 0 })
    let frag = (try { $p.properties.fragmentation.value | str replace "%" "" | into int } catch { 0 })
    let deg = (if $p.state == "ONLINE" { 0 } else { 1 })
    print $"zpool_health,pool=($p.name),state=($p.state) degraded=($deg)i,capacity=($cap)i,fragmentation=($frag)i"
  }
}

# Seconds until the step-ca SSH host cert expires. Silent on an un-enrolled host.
def "main ssh-cert" [] {
  let cert = "/var/lib/step-ssh/ssh_host_ed25519_key-cert.pub"
  if not ($cert | path exists) { return }
  let line = (^ssh-keygen -L -f $cert | lines | where {|l| $l | str contains "Valid:"} | first)
  let valid_to = ($line | split row " to " | last | str trim)
  if $valid_to == "forever" { return }
  let secs = ((($valid_to | into datetime) - (date now)) / 1sec | into int)
  print $"ssh_cert expiry_seconds=($secs)i"
}

def main [] {}
