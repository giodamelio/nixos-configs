# Enroll a host with the CA. Run on strontium (the CA) as root. For each kind
# named, mints a single-use token and prints the ready-to-paste command for the
# target host. Tokens expire (ssh: minutes, nfs: 30m) and die if step-ca
# restarts, so paste them right away.
#   sudo ca-enroll-host <hostname> ssh nfs
const ca_url = "https://ca.gio.ninja"
const ca_root = "/var/lib/gio-ca/root.crt"

# SSH host certificate, from the `bootstrap` provisioner. Its password is read
# from the *same* systemd credential step-ca-init uses (LoadCredentialEncrypted,
# resolved by name) via a transient unit.
def enroll-ssh [host: string] {
  let cred = "/run/credentials/ca-enroll-token.service/step_ca_provisioner_password"
  let token = (
    systemd-run --pipe --collect --quiet --unit=ca-enroll-token -p LoadCredentialEncrypted=step_ca_provisioner_password step ca token $host --ssh --host --principal $host --principal $"($host).gio.ninja" --provisioner bootstrap --provisioner-password-file $cred --ca-url $ca_url --root $ca_root
    | str trim
  )
  # step ssh certificate has no --out: it writes <keyfile-base>-cert.pub next to
  # the signed pubkey, so we copy the host pubkey into /var/lib/step-ssh first
  # and the cert lands at the path the renewer + sshd expect.
  $"sudo install -d -m0755 /var/lib/step-ssh && sudo cp /etc/ssh/ssh_host_ed25519_key.pub /var/lib/step-ssh/ssh_host_ed25519_key.pub && sudo step ssh certificate --host --sign --force --token '($token)' --ca-url ($ca_url) --root /etc/step/ca-root.crt ($host) /var/lib/step-ssh/ssh_host_ed25519_key.pub && sudo systemctl restart ssh-host-cert-renew.service"
}

# NFS host certificate, from the `nfs` provisioner (its password lives only on
# strontium, managed by step-ca-provisioners.service). The host's
# nfs-cert-enroll path unit consumes the token file and deletes it.
def enroll-nfs [host: string] {
  let fqdn = $"($host).gio.ninja"
  let token = (
    step ca token $fqdn --san $fqdn --san $host --provisioner nfs --provisioner-password-file /var/lib/gio-ca/provisioners/nfs/password --not-after 30m --ca-url $ca_url --root $ca_root
    | str trim
  )
  $"sudo install -D -m 0600 /dev/stdin /var/lib/step-nfs/enroll-token <<< '($token)'"
}

def main [host: string, ...kinds: string] {
  let enrollers = {
    ssh: {|h| enroll-ssh $h}
    nfs: {|h| enroll-nfs $h}
  }
  let known = ($enrollers | columns)
  if ($kinds | is-empty) {
    error make {msg: $"usage: ca-enroll-host <host> <kind>... \(kinds: ($known | str join ', '))"}
  }
  let unknown = ($kinds | where {|k| $k not-in $known})
  if not ($unknown | is-empty) {
    error make {msg: $"unknown kind\(s): ($unknown | str join ', ') \(kinds: ($known | str join ', '))"}
  }

  for kind in ($kinds | uniq) {
    let cmd = (do ($enrollers | get $kind) $host)
    print $"── ($kind) — run on ($host):"
    print ""
    print $cmd
    print ""
  }
}
