{
  root,
  debug,
  ...
}: {pkgs, ...}: {
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

  programs = {
    # ls
    eza = {
      enable = true;
      enableAliases = true;
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
