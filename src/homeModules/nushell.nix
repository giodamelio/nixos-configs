_: _: {
  programs.nushell = {
    enable = true;
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
