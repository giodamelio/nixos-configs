# atuind — run atuin in daemon mode (Linux user service). Converted from
# nix/modules/home/atuind.nix; the old `imports = [ ./atuin.nix ]` becomes an
# `includes` of the atuin aspect.
{den, ...}: {
  den.aspects.atuind = {
    includes = [den.aspects.atuin];
    homeManager = {
      pkgs,
      lib,
      ...
    }: {
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
    };
  };
}
