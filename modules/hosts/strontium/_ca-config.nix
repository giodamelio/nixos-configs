# step-ca provisioners and ca.json settings, shared by strontium and the VM tests.
{
  # Provisioners beyond the init-time `bootstrap`/`sshpop`, kept in ca.json by
  # step-ca-provisioners.service. Each gets its own key pair and a password
  # that never leaves the CA (under <caDir>/provisioners/<name>/).
  provisioners = {
    # NFS host certs (modules/aspects/nfs/cert.nix): X.509 only, 7 days,
    # renewed daily; no renewal after expiry, so a lapsed host re-enrolls.
    nfs = [
      "--ssh=false"
      "--x509-default-dur=168h"
      "--x509-max-dur=168h"
      "--x509-template=${./nfs-x509.tpl}"
    ];
    # Every gio.mtls certificate (modules/aspects/mtls), whatever its role.
    # Renewal after expiry stays off, so a stolen expired cert cannot renew.
    app = [
      "--ssh=false"
      "--x509-default-dur=168h"
      "--x509-max-dur=168h"
      "--allow-renewal-after-expiry=false"
      "--x509-template=${./app-x509.tpl}"
    ];
  };

  # Merged into ca.json on every start, so an existing ca.json picks them up.
  settings = {
    logger.format = "json";
    crl = {
      enabled = true;
      generateOnRevoke = true;
      cacheDuration = "24h";
      idpURL = "http://crl.gio.ninja/";
    };
  };
}
