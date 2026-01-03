{
  pkgs,
  flake,
  ...
}: let
  rustmailPackage = flake.packages.${pkgs.stdenv.hostPlatform.system}.rustmailer;
in {
  systemd.services.rustmailer = {
    description = "RustMailer Email Service";
    documentation = ["https://github.com/rustmailer/rustmailer-core"];
    after = ["network.target"];
    wantedBy = ["multi-user.target"];

    serviceConfig = {
      Type = "simple";
      DynamicUser = true;
      StateDirectory = "rustmailer";
      WorkingDirectory = "%S/rustmailer";

      # Main executable
      ExecStart = "${rustmailPackage}/bin/rustmailer";

      # Security hardening
      PrivateTmp = true;
      ProtectSystem = "full";
      NoNewPrivileges = true;
      RestrictSUIDSGID = true;

      # Auto-restart
      Restart = "on-failure";
      RestartSec = "5s";

      # Resource limits
      LimitNOFILE = 131072; # Support high number of concurrent sockets/files
      LimitNPROC = 10000; # Support async/thread-based concurrency
    };

    environment = {
      RUSTMAILER_ROOT_DIR = "%S/rustmailer";
      RUSTMAILER_HTTP_PORT = "15630";
      RUSTMAILER_GRPC_ENABLED = "true";
      RUSTMAILER_GRPC_PORT = "16630";
      RUSTMAILER_BIND_IP = "0.0.0.0";
      RUSTMAILER_PUBLIC_URL = "https://rustmailer.gio.ninja";
      RUSTMAILER_CORS_ORIGINS = "https://rustmailer.gio.ninja";
      RUSTMAILER_ENABLE_ACCESS_TOKEN = "true";
    };
  };

  services.gio.reverse-proxy = {
    enable = true;
    virtualHosts = {
      "rustmailer" = {
        host = "localhost";
        port = 15630;
      };
    };
  };
}
