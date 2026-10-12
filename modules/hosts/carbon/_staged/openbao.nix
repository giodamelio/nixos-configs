# openbao — single-node Raft secret store (openbao.gio.ninja); TLS terminated by
# Caddy. Converted from nix/hosts/carbon/openbao.nix.
_: {
  den.aspects.carbon.nixos = {
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

        storage.raft.path = "/var/lib/openbao";
      };
    };
  };

  den.hosts.x86_64-linux.carbon.services.openbao = {
    endpoint = {
      domain = "openbao";
      backend.host = "localhost";
      backend.port = 8200;
    };
    healthcheck.target = "https://openbao.gio.ninja/v1/sys/health?uninitcode=200&sealedcode=200&standbycode=200";
  };
}
