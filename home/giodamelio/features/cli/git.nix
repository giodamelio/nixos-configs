{ pkgs, lib, config, ... }: {
  programs.git = {
    enable = true;
    userName = "Giovanni d'Amelio";
    userEmail = "gio@damelio.net";
    aliases = {
      ci = "commit";
      st = "status";
      br = "branch";
      co = "checkout";
      chp = "cherry-pick";
      d = "diff";
      zco = "!git checkout $(git branch | fzf | cut -c 3-)";
      ca = "commit -am";
      h = "log --graph --pretty=format:'%Cred%h%Creset %G? -%C(yellow)%d%Creset %s %Cgreen(%ar) %C(bold blue)<%an>%Creset%n%-b' --abbrev-commit --date=relative";
      hp = "h --patch";
      amend = "commit --amend";
      remove-last = "reset --soft HEAD~1";
      remove-last-hard = "reset --hard HEAD~1";
      cdiff = "diff --cached";
      ldiff = "diff HEAD~1 HEAD";
      rh = "reset HEAD";
      rm-deleted = "!git ls-files --deleted -z | xargs -0 git rm";
      cb = "rev-parse --abbrev-ref HEAD";
      count = "rev-list --count";
      up = "pull --rebase --autostash";
      ignored = "status --ignored";
      fixup = "commit --amend -C HEAD";
    };
    delta = {
      enable = true;
    };
    extraConfig = {
      branch = {
        sort = "-authordate";
      };
    };
  };
}
