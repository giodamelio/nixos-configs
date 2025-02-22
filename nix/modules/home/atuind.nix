{ pkgs, lib, ...}: {
  imports = [
    ./atuin.nix
  ];

  config = lib.mkMerge [
    # Launch Daemon for SystemD
    (lib.mkIf pkgs.stdenv.hostPlatform.isLinux {
      systemd.user.services.atuind = {
        Unit.Description = "Atuin background daemon";
        Service = {
          Type = "exec";
          ExecStart = "${pkgs.atuin}/bin/atuin daemon";
          Restart = "on-failure";
          Environment = "ATUIN_LOG=info";
        };
        Install.WantedBy = ["default.target"];
      };
    })

    # Launch Daemon for Darwin
    (lib.mkIf pkgs.stdenv.hostPlatform.isDarwin {
      launchd.agents.atuind = {
        enable = true;
        config = {
          ProgramArguments = ["${pkgs.atuin}/bin/atuin" "daemon"];
          EnvironmentVariables.ATUIN_LOG = "info";
        };
      };
    })

    # Configure enable daemon mode
    {
      programs.atuin = {
        settings = {
          daemon.enabled = true;
        };
      };
    }
  ];
}
