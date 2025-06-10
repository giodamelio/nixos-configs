{
  pkgs,
  lib,
  ...
}: {
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
