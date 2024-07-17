_: {config, ...}: {
  programs.nushell = {
    enable = true;

    configFile.text = ''
      $env.config = {
        show_banner: false,
      }
    '';

    inherit (config.home) shellAliases;

    environmentVariables = {
      EDITOR = "nvim";
    };
  };

  programs.zoxide = {
    enableNushellIntegration = true;
  };

  programs.starship = {
    enableNushellIntegration = true;
  };

  programs.direnv = {
    enableNushellIntegration = true;
  };
}
