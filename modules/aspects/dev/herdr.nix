{inputs, ...}: {
  den.aspects.herdr.homeManager = {
    lib,
    perSystem,
    pkgs,
    ...
  }: {
    home.packages = [
      # Build herdr from our fork (carries the bwrap detection patch upstream).
      # zigDeps follows src because the package reads it off finalAttrs, but
      # cargoHash is taken from the original args, so vendor the fork ourselves.
      (pkgs.herdr.overrideAttrs (final: _: {
        src = inputs.herdr;
        # nixpkgs' version would fail versionCheckPhase whenever it moves past the fork
        inherit ((lib.importTOML "${inputs.herdr}/Cargo.toml").package) version;
        cargoDeps = pkgs.rustPlatform.fetchCargoVendor {
          inherit (final) pname version src;
          hash = "sha256-B5i/JHbZw/654D09zOeQc3+wg1zgA72EprcITddtexo=";
        };
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
