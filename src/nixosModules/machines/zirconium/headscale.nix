{root, ...}: {config, ...}: {
  imports = [];

  config = {
    # Start the headscale server
    services.headscale = {
      enable = true;

      settings = {
        server_url = "https://headscale.gio.ninja:443";
      };
    };

    # Use Caddy to reverse proxy
    services.caddy = {
      enable = true;
      virtualHosts."https://headscale.gio.ninja" = {
        extraConfig = ''
          reverse_proxy http://localhost:8080
        '';
      };
    };

    # Join the tailscale network
    services.tailscale = {
      enable = true;
      extraUpFlags = [
        "--login-server"
        "https://headscale.gio.ninja"
      ];
    };
  };
}
