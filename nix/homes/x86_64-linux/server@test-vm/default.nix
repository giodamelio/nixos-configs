{ pkgs, ... }: {
  programs.git = {
    enable = true;
    aliases.st = "status";
  };

  home = {
    packages = with pkgs; [
      htop
    ];

    stateVersion = "24.11";
  };
}
