{pkgs, ...}: let
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
  imports = [
    ./aliases.nix
  ];

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
    };

    # Setup Git Large File Storage
    lfs.enable = true;

    # Add some global gitignores
    ignores = [
      "tmp/"
      ".direnv/"
      ".aider*"
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
}
