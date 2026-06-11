# git — git config, send-email via Fastmail/1Password, difftastic, and my alias
# set. Converted from nix/modules/home/git/{default,aliases}.nix — the two
# Blueprint files are folded into one aspect (the alias block was its own
# imported module; here it's just a second attrset in the body).
_: {
  den.aspects.git.homeManager = {pkgs, ...}: let
    # Credential helper for git send-email with Fastmail
    # Retrieves SMTP password from 1Password
    git-credential-fastmail = pkgs.writeShellScriptBin "git-credential-fastmail" ''
      if [ "''${1:-}" != "get" ]; then
        exit 0
      fi

      # Read and discard stdin (required by credential helper protocol)
      cat > /dev/null

      echo "password=$(op item get iwwf7t34ijmbn6wxic4yakjah4 --reveal --fields=password)"
    '';
  in {
    programs.git = {
      enable = true;

      settings = {
        user = {
          name = "Giovanni d'Amelio";
          email = "gio@damelio.net";
        };

        # New branch name for default inits
        init.defaultBranch = "main";

        # Setup send-email
        sendemail = {
          smtpServer = "smtp.fastmail.com";
          smtpUser = "giodamelio@fastmail.com";
          smtpEncryption = "ssl";
          smtpPort = 465;
          confirm = "always";
        };

        # Credential helper for Fastmail SMTP (used by send-email)
        credential."smtp://giodamelio%40fastmail.com@smtp.fastmail.com:465".helper = "${git-credential-fastmail}/bin/git-credential-fastmail";

        # Aliases (was nix/modules/home/git/aliases.nix)
        alias = {
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

          # Makes it interactive, force and works with directories
          cleanitup = "clean -ifd";

          # Aliases that require external commands
          pcb = "!git push origin $(git rev-parse --abbrev-ref HEAD)";
          rm-deleted = "!git ls-files --deleted -z | xargs -0 git rm";
        };
      };

      # Setup Git Large File Storage
      lfs.enable = true;

      # Add some global gitignores
      ignores = [
        "tmp/"
        ".direnv/"
        ".aider*"
        ".sandbox-paths"
      ];

      includes = [
        {path = "~/.gitconfig.extra";}
      ];
    };

    # Language aware diffing powered by Treesitter
    programs.difftastic = {
      enable = true;
      git.enable = true;
    };

    # Install Git Absorb for easy automatic fixups
    home.packages = [
      pkgs.git-absorb
    ];
  };
}
