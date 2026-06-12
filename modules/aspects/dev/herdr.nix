{inputs, ...}: {
  den.aspects.herdr.homeManager = {perSystem, ...}: {
    home.packages = [
      # Build herdr from our fork (carries the bwrap detection patch upstream).
      (perSystem.llm-agents.herdr.overrideAttrs (_: {
        src = inputs.herdr;
      }))
      perSystem.self.herdr-proxy
    ];

    systemd.user.sockets.herdr-proxy = {
      Unit.Description = "Herdr sandbox proxy socket";

      Socket = {
        ListenStream = "%t/herdr-proxy.sock";
        SocketMode = "0600";
        RemoveOnStop = true;
      };

      Install.WantedBy = ["sockets.target"];
    };

    systemd.user.services.herdr-proxy = {
      Unit.Description = "Herdr sandbox proxy";

      Service = {
        ExecStart = "${perSystem.self.herdr-proxy}/bin/herdr-proxy";

        Environment = [
          "REAL_SOCKET=%h/.config/herdr/herdr.sock"
        ];

        StandardOutput = "journal";
        StandardError = "journal";

        NoNewPrivileges = true;
        PrivateTmp = true;
        RestrictAddressFamilies = "AF_UNIX";
        ProtectSystem = "strict";
        ProtectHome = "read-only";
        ReadWritePaths = [
          "%h/.config/herdr"
        ];
      };
    };
  };
}
