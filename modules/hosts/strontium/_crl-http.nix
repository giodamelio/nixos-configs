# Plain-HTTP http://crl.gio.ninja/ in front of step-ca's /1.0/crl, shared by
# strontium and the mtls VM test. The CRL is signed by the CA, so the transport
# needs no trust, and verifiers never need TLS to check TLS.
{
  caRoot,
  caPort,
}: {
  services.nginx = {
    enable = true;
    virtualHosts."crl.gio.ninja" = {
      default = true;
      locations."= /" = {
        proxyPass = "https://127.0.0.1:${toString caPort}/1.0/crl";
        # step-ca's own TLS cert names ca.gio.ninja, not 127.0.0.1.
        extraConfig = ''
          proxy_ssl_trusted_certificate ${caRoot};
          proxy_ssl_verify on;
          proxy_ssl_verify_depth 2;
          proxy_ssl_server_name on;
          proxy_ssl_name ca.gio.ninja;
        '';
      };
      locations."/".return = "404";
    };
  };

  networking.firewall.allowedTCPPorts = [80];
}
