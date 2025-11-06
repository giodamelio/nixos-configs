{pkgs, ...}: let
  restateConfig = {
    cluster-name = "restate";
    node-name = "carbon";
    bind-address = "127.0.0.1:5122";
    auto-provision = true; # Disable if we ever go multi node

    log-filter = "info";
    log-format = "json";

    disable-telemetry = true;

    ingress = {
      bind-address = "127.0.0.1:8080";
      advertised-ingress-endpoint = "https://ingress.restate.gio.ninja";
    };

    admin = {
      bind-address = "127.0.0.1:9070";
      advertised-admin-endpoint = "https://admin.restate.gio.ninja";
    };
  };

  configFile = (pkgs.formats.toml {}).generate "restate.toml" restateConfig;
in {
  environment.systemPackages = with pkgs; [
    restate
  ];

  systemd.services.restate = {
    description = "Restate distributed application platform";
    wantedBy = ["multi-user.target"];
    after = ["network-online.target"];
    wants = ["network-online.target"];

    serviceConfig = {
      ExecStart = "${pkgs.restate}/bin/restate-server --config-file ${configFile}";

      # Dynamic user and state management
      DynamicUser = true;
      StateDirectory = "restate";
      WorkingDirectory = "/var/lib/restate";

      # Security hardening
      CapabilityBoundingSet = "";
      LockPersonality = true;
      NoNewPrivileges = true;
      PrivateDevices = true;
      PrivateTmp = true;
      PrivateUsers = true;
      ProcSubset = "pid";
      ProtectClock = true;
      ProtectControlGroups = true;
      ProtectHome = true;
      ProtectHostname = true;
      ProtectKernelLogs = true;
      ProtectKernelModules = true;
      ProtectKernelTunables = true;
      ProtectProc = "invisible";
      ProtectSystem = "strict";
      RemoveIPC = true;
      RestrictAddressFamilies = ["AF_INET" "AF_INET6" "AF_UNIX"];
      RestrictNamespaces = true;
      RestrictRealtime = true;
      RestrictSUIDSGID = true;
      SystemCallArchitectures = "native";
      SystemCallFilter = ["@system-service" "~@privileged"];
      UMask = "0077";

      # Support for encrypted credentials
      LoadCredentialEncrypted = [];

      # Restart policy
      Restart = "on-failure";
      RestartSec = "10s";
    };
  };

  services.gio.reverse-proxy = {
    enable = true;
    virtualHosts = {
      "admin.restate" = {
        host = "localhost";
        port = 9070;
      };
      "ingress.mealie" = {
        host = "localhost";
        port = 8080;
      };
    };
  };
}
