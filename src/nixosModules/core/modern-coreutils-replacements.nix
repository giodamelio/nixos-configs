_: {pkgs, ...}: {
  environment.systemPackages = with pkgs; [
    fd # find
    procs # ps
    sd # sed
    du-dust # du
  ];

  home-manager.users.giodamelio = _: {
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
      };

      ripgrep.enable = true; # grep
      bat.enable = true; # cat
    };
  };
}
