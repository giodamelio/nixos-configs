{...}: {
  pkgs,
  config,
  ...
}: {
  age.secrets.cert_firezone_gio_ninja.file = ../../../secrets/cert_cloudflare_gio_ninja.age;

  # Get HTTPS certificates from LetsEncrypt for Firezone
  security.acme = {
    acceptTerms = true;
    defaults.email = "gio@damelio.net";

    certs."firezone.gio.ninja" = {
      dnsProvider = "cloudflare";
      credentialsFile = config.age.secrets.cert_firezone_gio_ninja.path;
    };
  };
}
