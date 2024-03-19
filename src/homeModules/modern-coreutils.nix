_: {pkgs, ...}: {
  home.packages = [
    # find
    pkgs.fd

    # ps
    pkgs.procs

    # sed
    pkgs.sd

    # du
    pkgs.du-dust
  ];

  home.shellAliases = {
    tree = "eza --tree";
    du = "dust";
    ps = "procs";
  };

  programs = {
    # ls
    eza = {
      enable = true;
      enableBashIntegration = true;
      enableZshIntegration = true;
      enableNushellIntegration = true;
    };

    # grep
    ripgrep = {
      enable = true;
    };

    # cat
    bat = {
      enable = true;
    };
  };
}
