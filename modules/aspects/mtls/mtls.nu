# Enroll and renew this host's gio.mtls certificates. `certs` (name -> declared
# identity and files), `host` and `ca_root` are prepended at build time.
const ca_url = "https://ca.gio.ninja"
const tokens_dir = "/var/lib/mtls/tokens"

def step-ca-args [] {
  [--ca-url $ca_url --root $ca_root]
}

# Run an external command, failing with its stderr.
def --wrapped must [cmd: string, ...args: string] {
  let r = (^$cmd ...$args | complete)
  if $r.exit_code != 0 {
    error make {msg: $"($cmd) ($args | first 2 | str join ' ') failed: ($r.stderr | str trim)"}
  }
  $r.stdout
}

def inspect [file: string] {
  must step certificate inspect --format json $file | from json
}

def identity-of [file: string] {
  let c = (inspect $file)
  let san = ($c.extensions?.subject_alt_name? | default {})
  {
    cn: ($c.subject?.common_name? | default [])
    o: ($c.subject?.organization? | default [])
    ou: ($c.subject?.organizational_unit? | default [])
    uri: ($san.uniform_resource_identifiers? | default [])
    dns: ($san.dns_names? | default [] | sort)
    ip: ($san.ip_addresses? | default [] | sort)
  }
}

# The fields of the certificate in `file` that differ from the declaration.
def drift [cert: record, file: string] {
  let want = {cn: [$cert.cn], o: ["app"], ou: [$cert.role], uri: [$cert.uri], dns: $cert.dns, ip: $cert.ips}
  let have = (identity-of $file)
  $want
  | columns
  | where {|k| ($want | get $k) != ($have | get $k)}
  | each {|k| $"($k) is ($have | get $k | to nuon), declared ($want | get $k | to nuon)"}
}

def secure [cert: record] {
  for f in [$cert.keyFile $cert.certFile] {
    must chown $"root:($cert.group)" $f
    must chmod 0640 $f
  }
}

# A fresh enrollment may follow units that failed for want of the files, so it
# starts them; a renewal only touches units that are running.
def on-renew [cert: record, fresh: bool] {
  let restart = if $fresh { "restart" } else { "try-restart" }
  let reload = if $fresh { "reload-or-restart" } else { "try-reload-or-restart" }
  let units = if $cert.onRenew == "reload-caddy" { ["caddy.service"] } else { $cert.units }
  if ($units | is-empty) { return }
  let verb = if $cert.onRenew == "restart" { $restart } else { $reload }
  must systemctl $verb ...$units | ignore
}

def report [what: string, failures: list<string>] {
  if not ($failures | is-empty) {
    print -e $"mtls-($what) failed for: ($failures | str join ', ')"
    exit 1
  }
}

def enroll-one [name: string, token: string] {
  if $name not-in ($certs | columns) {
    error make {msg: "no gio.mtls.certs declaration has this name"}
  }
  let cert = ($certs | get $name)
  let new_cert = $"($cert.certFile).new"
  let new_key = $"($cert.keyFile).new"
  # No --san: the CLI copies the token's SANs into the request.
  must step ca certificate --force ...(step-ca-args) --token $token $cert.cn $new_cert $new_key | ignore
  let d = (drift $cert $new_cert)
  if not ($d | is-empty) {
    rm -f $new_cert $new_key
    error make {msg: $"issued certificate does not match the declaration, re-run ca-enroll-host: ($d | str join '; ')"}
  }
  # Key first: the renewer treats cert.pem as "enrolled".
  mv -f $new_key $cert.keyFile
  mv -f $new_cert $cert.certFile
  secure $cert
  on-renew $cert true
  print $"($name): enrolled as ($cert.cn)"
}

def "main enroll" [] {
  mut failures = []
  for file in (glob $"($tokens_dir)/*.token" | sort) {
    let name = ($file | path parse | get stem)
    let token = (open --raw $file | str trim)
    # Removed before use: a failed enrollment must not re-trigger the path unit,
    # and the token is single-use either way.
    rm -f $file
    let err = (try { enroll-one $name $token; null } catch {|e| $e.msg })
    if $err != null {
      print -e $"($name): ($err)"
      $failures = ($failures | append $name)
    }
  }
  report enroll $failures
}

def renew-one [name: string, cert: record] {
  let d = (drift $cert $cert.certFile)
  if not ($d | is-empty) {
    error make {msg: $"identity drift, not renewing; reissue with `ca-enroll-host ($host) mtls` on strontium: ($d | str join '; ')"}
  }
  let before = (inspect $cert.certFile | get serial_number)
  must step ca renew --force --expires-in 120h ...(step-ca-args) $cert.certFile $cert.keyFile | ignore
  if (inspect $cert.certFile | get serial_number) != $before {
    secure $cert
    on-renew $cert false
    print $"($name): renewed"
  }
}

def "main renew" [] {
  mut failures = []
  for name in ($certs | columns | sort) {
    let cert = ($certs | get $name)
    if not ($cert.certFile | path exists) {
      print $"($name): not enrolled yet, skipping"
      continue
    }
    let err = (try { renew-one $name $cert; null } catch {|e| $e.msg })
    if $err != null {
      print -e $"($name): ($err)"
      $failures = ($failures | append $name)
    }
  }
  report renew $failures
}

def main [] {
  error make {msg: "usage: mtls enroll|renew"}
}
