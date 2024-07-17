_: {pkgs, ...}: {
  programs.zsh = {
    enable = true;
    enableCompletion = true;
  };

  programs.atuin = {
    enable = true;
    enableZshIntegration = true;
    settings = {
      filter_mode_shell_up_key_binding = "session";
      daemon.enabled = true;
    };
  };

  systemd.user.services.atuind = {
    Install = {
      After = [ "network.target" ];
      WantedBy = [ "default.target" ];
    };
    Service = {
      ExecStart = "${pkgs.atuin}/bin/atuin daemon";
      Environment = "ATUIN_LOG=info";
    };
  };

  programs.zoxide = {
    enable = true;
    enableZshIntegration = true;
  };

  programs.starship = {
    enableZshIntegration = true;
  };

  programs.nnn = {
    enable = true;
  };

  programs.direnv = {
    enable = true;
    enableBashIntegration = true;
    enableZshIntegration = true;
    nix-direnv.enable = true;
  };
}
