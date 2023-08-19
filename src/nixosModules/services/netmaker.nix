{...}: {
  pkgs,
  config,
  ...
}: let
  lib = pkgs.lib;
in {
  # Load our secrets
  age.secrets.cert_firezone_gio_ninja.file = ../../../secrets/cert_cloudflare_gio_ninja.age;

  # Get HTTPS certificates from LetsEncrypt for Firezone
  security.acme = {
    acceptTerms = true;
    defaults.email = "gio@damelio.net";

    certs."nm.gio.ninja" = {
      dnsProvider = "cloudflare";
      domain = "*.nm.gio.ninja";
      extraDomainNames = ["nm.gio.ninja"];
      credentialsFile = config.age.secrets.cert_firezone_gio_ninja.path;
    };
  };
}
