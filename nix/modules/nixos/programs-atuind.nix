{
  pkgs,
  lib,
  ...
}: {
  home-manager.users.giodamelio = _:
    lib.mkMerge [
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

      # Configure Atuin
      {
        programs.atuin = {
          enable = true;
          enableZshIntegration = true;
          enableNushellIntegration = true;

          settings = {
            filter_mode_shell_up_key_binding = "session";
            daemon.enabled = true;
          };
        };
      }
    ];
}
