_: _: {
  programs.nushell = {
    enable = true;

    configFile.text = ''
      $env.config = {
        show_banner: false,
      }
    '';
  };

  programs.atuin = {
    enableNushellIntegration = true;
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
