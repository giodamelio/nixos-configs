{
  programs.atuin = {
    enable = true;
    enableZshIntegration = true;
    enableNushellIntegration = true;

    settings = {
      filter_mode_shell_up_key_binding = "session";
    };
  };
}
