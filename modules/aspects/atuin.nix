# atuin — shell history sync/search. Converted from nix/modules/home/atuin.nix.
_: {
  den.aspects.atuin.homeManager = {
    programs.atuin = {
      enable = true;
      enableZshIntegration = true;
      enableNushellIntegration = true;

      settings = {
        filter_mode_shell_up_key_binding = "session";
      };
    };
  };
}
