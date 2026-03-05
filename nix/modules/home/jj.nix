{pkgs, ...}: {
  programs.jujutsu = {
    enable = true;
    settings = {
      user = {
        name = "Giovanni d'Amelio";
        email = "gio@damelio.net";
      };

      ui = {
        diff-formatter = ["difft" "--color=always" "$left" "$right"];
        default-command = "status";
      };

      git = {
        private-commits = "description(glob:'wip*') | description(glob:'WIP*') | description(glob:'private:*') | description('scratch')";
        write-change-id-header = true;
      };

      aliases = {
        "e" = ["edit"];
      };
    };
  };

  home.packages = with pkgs; [
    difftastic
  ];
}
