{root, ...}: {pkgs, ...}: let
  inherit (root.packages.scripts {inherit pkgs;}) wallpaper-epic-downloader;
in {
  systemd.user.services.update-wallpaper = {
    Unit = {
      Description = "Automatically update the wallpaper";
    };

    Service = {
      Type = "oneshot";
      ExecStart = "${wallpaper-epic-downloader}/bin/wallpaper-epic-downloader";
      RemainAfterExit = "yes";
    };

    Install = {
      WantedBy = ["default.target"];
    };
  };
  systemd.user.timers.update-wallpaper = {
    Unit.Description = "Update the wallpaper";
    Timer = {
      OnCalendar = "*:0/30"; # Every 30 minutes
      Persistent = true;
    };
    Install.WantedBy = ["timers.target"];
  };
}
