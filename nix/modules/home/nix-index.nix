{inputs, ...}: {
  imports = [
    inputs.nix-index-database.homeModules.nix-index
  ];

  programs.nix-index-database.comma.enable = true;

  programs.nix-index = {
    enable = true;
    enableZshIntegration = true;
  };

  # # TODO: contribute this back to the HomeManager module
  # # https://github.com/nix-community/home-manager/blob/master/modules/programs/nix-index.nix
  # # Example: https://github.com/nix-community/home-manager/blob/6a20e40acaebf067da682661aa67da8b36812606/modules/services/borgmatic.nix#L45
  # systemd.user.services.nix-index-update = {
  #   Unit = {
  #     Description = "Update the nix-index index";
  #
  #     # Prevent index update unless computer is plugged into the wall
  #     ConditionACPower = true;
  #   };
  #
  #   Service = {
  #     Type = "oneshot";
  #     ExecStart = "${pkgs.nix-index}/bin/nix-index";
  #
  #     # Lower CPU and I/O priority:
  #     Nice = 19;
  #     CPUSchedulingPolicy = "batch";
  #     IOSchedulingClass = "best-effort";
  #     IOSchedulingPriority = 7;
  #     IOWeight = 100;
  #   };
  #
  #   Install = {
  #     WantedBy = ["default.target"];
  #   };
  # };
  # systemd.user.timers.nix-index-update = {
  #   Unit.Description = "Update the nix-index index";
  #   Timer = {
  #     OnCalendar = "daily";
  #     Persistent = true;
  #     RandomizedDelaySec = "10m";
  #   };
  #   Install.WantedBy = ["timers.target"];
  # };
}
