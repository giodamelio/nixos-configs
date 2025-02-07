_: {
  programs.nushell = {
    enable = true;

    configFile.text = ''
      $env.config = {
        show_banner: false,
      }
    '';

    # TODO: re-enable
    # There are extra ones getting in here somehow
    # inherit (config.home) shellAliases;

    environmentVariables = {
      EDITOR = "'nvim'";
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
