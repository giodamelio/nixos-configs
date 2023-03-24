{ pkgs, lib, config, ... }: {
  programs.atuin = {
    enable = true;
    enableFishIntegration = true;
  };
}
