_: _: {
  services.caddy = {
    enable = true;

    globalConfig = ''
      email admin@gio.ninja

      # FIXME: I know I am not supposed to hardcode these
      import /run/credentials/caddy.service/caddy-cloudflare-config
    '';
  };

  systemd.services.caddy = {
    serviceConfig = {
      # I don't understand how Caddy is ever working without this...
      AmbientCapabilities = "CAP_NET_BIND_SERVICE";

      # Load the cloudflare config
      LoadCredentialEncrypted = "caddy-cloudflare-config";
    };
  };

  networking.firewall.interfaces."wg0" = {
    allowedTCPPorts = [443 80];
  };
  networking.firewall.interfaces."wg9" = {
    allowedTCPPorts = [443 80];
  };
}
