{ pkgs, ...} : {
  home.packages = with pkgs; [
    dust
    procs
  ];

  home.shellAliases = {
    tree = "eza --tree";
    du = "dust";
    ps = pkgs.lib.getExe pkgs.procs;
  };

  programs = {
    # ls
    eza = {
      enable = true;
      enableBashIntegration = true;
      enableZshIntegration = true;
    };

    ripgrep.enable = true; # grep
    bat.enable = true; # cat
  };
}
