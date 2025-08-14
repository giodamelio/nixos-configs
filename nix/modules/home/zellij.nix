{
  pkgs,
  lib,
  ...
}: {
  programs.zellij = {
    enable = true;
  };

  # Manually setup completions and not auto start
  # programs.zellij.enableZshIntegration just adds auto start
  programs.zsh.initContent = lib.mkOrder 551 ''
    eval "$(${lib.getExe pkgs.zellij} setup --generate-completion zsh)"
  '';

  # Manually set KDL config string, since the HM module is not in great shape right now
  xdg.configFile."zellij/config.kdl".text = ''
    keybinds {}
  '';
}
