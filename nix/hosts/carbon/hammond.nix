{inputs, ...}: {
  imports = [
    inputs.quadlet-nix.nixosModules.quadlet
  ];

  virtualisation.quadlet.autoEscape = true;
  virtualisation.quadlet.containers.hammond = {
    autoStart = true;
    containerConfig = {
      image = "localhost/hammond:latest";
      pull = "never";
      networks = ["podman"];
      volumes = [
        "/var/lib/hammond/state:/app/state"
        "/var/lib/hammond/cache:/app/.cache"
      ];
      publishPorts = [
        "4000:4000"
      ];
      environments = {
        DATABASE_PATH = "/app/state/hammond.db";
        PHX_HOST = "hammond.gio.ninja";
        DISCORD_APPLICATION_ID = "1396957121475645500";
      };
      secrets = [
        "hammond_secret_key_base,type=env,target=SECRET_KEY_BASE"
        "hammond_discord_bot_token,type=env,target=DISCORD_BOT_TOKEN"
        "hammond_openrouter_api_key,type=env,target=OPENROUTER_API_KEY"
      ];
    };
  };

  services.gio.reverse-proxy = {
    enable = true;
    virtualHosts = {
      "hammond" = {
        host = "localhost";
        port = 4000;
      };
    };
  };
}
