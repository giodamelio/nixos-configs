# Revoke the current certificate for a CN issued by the `app` provisioner. Run
# on strontium (the CA) as root:
#   sudo ca-revoke <cn>
# Every renewal issues a new serial, so only the newest one in step-ca's JSON
# journal is the certificate in use; revoking an older serial changes nothing.
const ca_url = "https://ca.gio.ninja"
const ca_root = "/var/lib/gio-ca/root.crt"

def main [cn: string] {
  let issued = (
    journalctl --unit step-ca.service --output cat --no-pager
    | lines
    | where {|l| ($l | str starts-with "{") and ($l | str contains $cn)}
    | each {|l| try { $l | from json } catch { null } }
    | compact
    | where {|e| $e.subject? == $cn and $e.serial? != null and $e.status? in [200 201]}
  )
  if ($issued | is-empty) {
    error make {msg: $"no certificate for CN ($cn) in the step-ca journal"}
  }
  let newest = ($issued | last)
  print $"revoking ($cn) serial ($newest.serial) \(($newest.path), valid ($newest.'valid-from'?) to ($newest.'valid-to'?))"

  let token = (
    step ca token $newest.serial --revoke --provisioner app --provisioner-password-file /var/lib/gio-ca/provisioners/app/password --ca-url $ca_url --root $ca_root
    | str trim
  )
  step ca revoke --token $token --ca-url $ca_url --root $ca_root $newest.serial
}
