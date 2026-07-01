# Enroll a host into the SSH CA. Run on strontium (the CA) as root. Mints a
# single-use token — reading the provisioner password from the *same* systemd
# credential step-ca-init uses (LoadCredentialEncrypted, resolved by name, not a
# hardcoded path or a prompt) via a transient unit — and prints the ready-to-
# paste command for the target host.
#   sudo ca-enroll-host <hostname>
def main [host: string] {
  let cred = "/run/credentials/ca-enroll-token.service/step-ca-provisioner-password"
  let token = (
    systemd-run --pipe --collect --quiet --unit=ca-enroll-token -p LoadCredentialEncrypted=step-ca-provisioner-password step ca token $host --ssh --host --principal $host --principal $"($host).gio.ninja" --provisioner bootstrap --provisioner-password-file $cred --ca-url https://ca.gio.ninja --root /var/lib/gio-ca/root.crt
    | str trim
  )

  # step ssh certificate has no --out: it writes <keyfile-base>-cert.pub next to
  # the signed pubkey, so we copy the host pubkey into /var/lib/step-ssh first
  # and the cert lands at the path the renewer + sshd expect.
  let host_cmd = $"sudo install -d -m0755 /var/lib/step-ssh && sudo cp /etc/ssh/ssh_host_ed25519_key.pub /var/lib/step-ssh/ssh_host_ed25519_key.pub && sudo step ssh certificate --host --sign --force --token '($token)' --ca-url https://ca.gio.ninja --root /etc/step/ca-root.crt ($host) /var/lib/step-ssh/ssh_host_ed25519_key.pub && sudo systemctl restart ssh-host-cert-renew.service"

  print $"One-time enrollment token for ($host) \(expires shortly):"
  print $token
  print ""
  print "Run this on the new host:"
  print ""
  print $host_cmd
}
