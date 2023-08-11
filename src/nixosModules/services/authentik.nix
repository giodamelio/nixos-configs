{...}: {
  pkgs,
  config,
  ...
}: {
  environment = {
    systemPackages = with pkgs; [
      # Easily connect to the Redis REPL
      (writeShellApplication {
        name = "connect-redis";
        runtimeInputs = [redis];
        text = let
          redisConfig = config.services.redis.servers.authentik;
        in ''
          sudo -u ${redisConfig.user} redis-cli -s ${redisConfig.unixSocket}
        '';
      })
    ];
  };

  # Start our own Redis server
  services.redis.servers.authentik = {
    enable = true;
  };

  # Mount some secrets for the service
  services.vault-agent.instances.authentik = {
    enable = true;
    settings = {
      vault = [
        {
          address = "http://127.0.0.1:8200";
        }
      ];
      auto_auth = [
        {
          method = [
            {
              type = "approle";
              config = {
                role_id_file_path = "/var/run/credentials/vault-agent-authentik/role_id";
                secret_id_file_path = "/var/run/credentials/vault-agent-authentik/secret_id";
              };
            }
          ];
        }
      ];
      template = [
        {
          destination = "/var/run/testing";
          contents = ''
            Hello World!
          '';
          error_on_missing_key = true;
        }
      ];
    };
  };
}
