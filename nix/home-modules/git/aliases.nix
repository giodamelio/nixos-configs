_: {
  programs.git.aliases = {
    ci = "commit";
    st = "status";
    br = "branch";
    co = "checkout";
    chp = "cherry-pick";
    d = "diff";
    ca = "commit -am";
    h = "log --graph --pretty=format:'%Cred%h%Creset %G? -%C(yellow)%d%Creset %s %Cgreen(%ar) %C(bold blue)<%an>%Creset%n%-b' --abbrev-commit --date=relative";
    hp = "h --patch";
    amend = "commit --amend";
    remove-last = "reset --soft HEAD~1";
    remove-last-hard = "reset --hard HEAD~1";
    cdiff = "diff --cached";
    ldiff = "diff HEAD~1 HEAD";
    rh = "reset HEAD";
    cb = "rev-parse --abbrev-ref HEAD";
    count = "rev-list --count";
    up = "pull --rebase --autostash";
    ignored = "status --ignored";
    fixup = "commit --amend -C HEAD";

    # Aliases that require external commands
    pcb = "!git push origin $(git rev-parse --abbrev-ref HEAD)";
    rm-deleted = "!git ls-files --deleted -z | xargs -0 git rm";
  };
}
