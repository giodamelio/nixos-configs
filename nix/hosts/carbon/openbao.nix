_: {
  services.openbao = {
    enable = true;
    settings = {
      ui = true;
      listener.default = {
        type = "tcp";
        address = "127.0.0.1:8200";
        tls_disable = true;
      };

      api_addr = "https://openbao.gio.ninja";
      cluster_addr = "http://127.0.0.1:8201";

      # Store using the built in Raft. We are just using a single node though
      storage.raft.path = "/var/lib/openbao";
    };
  };

  services.gio.reverse-proxy = {
    enable = true;
    virtualHosts.openbao = {
      host = "localhost";
      port = 8200;
    };
  };

  gio.services.openbao.consul = {
    name = "openbao";
    address = "openbao.gio.ninja";
    port = 443;
    checks = [
      {
        http = "https://openbao.gio.ninja/v1/sys/health?uninitcode=200&sealedcode=200&standbycode=200";
        interval = "60s";
      }
    ];
  };
}
