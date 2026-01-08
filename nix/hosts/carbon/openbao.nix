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
}
