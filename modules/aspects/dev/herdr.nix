{inputs, ...}: {
  den.aspects.herdr.homeManager = {perSystem, ...}: {
    home.packages = [
      # Build herdr from our fork (carries the bwrap detection patch upstream).
      # The fork's Cargo.lock differs from upstream, so the cargo vendor dir
      # hashes differently. Upstream's cargoHash is read from args (not finalAttrs),
      # so overrideAttrs can't set it; instead override the FOD hash on the inner
      # vendorStaging derivation that fetchCargoVendor produces.
      (perSystem.llm-agents.herdr.overrideAttrs (old: {
        version = "0.7.2";
        src = inputs.herdr;
        # versionCheckHook runs `herdr --help` and greps for the version; the
        # fork's help output doesn't carry it, so the smoke check fails on a
        # binary that's otherwise fine. Skip it.
        doInstallCheck = false;
        cargoDeps = old.cargoDeps.overrideAttrs (vendor: {
          vendorStaging = vendor.vendorStaging.overrideAttrs (_: {
            outputHash = "sha256-TtQE1RvlTameGr81cMUeAQaRKS3hwo7I2ex/GHQgLik=";
          });
        });
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
