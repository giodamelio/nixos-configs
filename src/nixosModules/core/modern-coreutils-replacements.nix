_: {pkgs, ...}: {
  environment.systemPackages = with pkgs; [
      fd # find
      procs # ps
      sd # sed
      du-dust # du
  ];

  home-manager.users.giodamelio =  { pkgs, ... }: {
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

      ripgrep.enable = true; # grep
      bat.enable = true; # cat
    };
  };
}
