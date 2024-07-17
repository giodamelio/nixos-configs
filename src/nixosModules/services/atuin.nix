_: { pkgs, ...} : {
  # Run Atuin daemon
  systemd.user.services.atuind = {
    enable = true;
    after = [ "network.target" ];
    wantedBy = [ "default.target" ];
    serviceConfig = {
      ExecStart = "${pkgs.atuin}/bin/atuin daemon";
    };
    environment = {
      ATUIN_LOG = "info";
    };
  };

  home-manager.users.giodamelio =  { pkgs, ... }: {
    # Enable Atuin in daemon mode
    programs.atuin = {
      enable = true;
      enableZshIntegration = true;
      enableNushellIntegration = true;

      settings = {
        filter_mode_shell_up_key_binding = "session";
        daemon.enabled = true;
      };
    };
  };
}
