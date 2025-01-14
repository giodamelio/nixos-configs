{pkgs, ...}: {
  programs.git = {
    enable = true;
  };

  home = {
    packages = with pkgs; [
      htop
    ];

    stateVersion = "24.11";
  };
}
