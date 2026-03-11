{
  pkgs,
  flake,
  ...
}: let
  jj-push = flake.lib.writeNushellApplication pkgs {
    name = "jj-push";
    source = ''
      def main [...args] {
        if not (which prek | is-empty) {
          prek run -a
          if $env.LAST_EXIT_CODE != 0 {
            exit $env.LAST_EXIT_CODE
          }
        }
        jj git push ...$args
      }
    '';
  };
in {
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
        "logall" = ["log" "-r" "all()"];

        # Update the current bookmark to the current or last commit
        "tug" = ["bookmark" "move" "--from" "heads(::@- & bookmarks())" "--to" "@"];
        "tug-" = ["bookmark" "move" "--from" "heads(::@- & bookmarks())" "--to" "@-"];
        "push" = ["util" "exec" "--" "jj-push"];
      };
    };
  };

  home.packages = [
    pkgs.difftastic
    pkgs.lazyjj
    jj-push
  ];

  # If we are using JJ update our shell prompt to display it
  # This will disable the git modules when it detects a jj repo
  # It does that by disabling the default git modules then re-invoking them with a conditional
  programs.starship = {
    settings = let
      mkOverridedGit = starship_module: {
        when = "! jj --ignore-working-copy root";
        command = "starship module ${starship_module}";
        description = "Only show ${starship_module} if we're not in a jj repo";
        style = "";
      };
    in {
      # First disable the built in modules
      git_status.disabled = true;
      git_commit.disabled = true;
      git_metrics.disabled = true;
      git_branch.disabled = true;

      # Add back the overridden version
      custom.git_status = mkOverridedGit "git_status";
      custom.git_commit = mkOverridedGit "git_commit";
      custom.git_metrics = mkOverridedGit "git_metrics";
      custom.git_branch = mkOverridedGit "git_branch";

      # Add new module to show JJ status
      custom.jj = {
        description = "The current jj status";
        when = "jj --ignore-working-copy root";
        symbol = "🥋 ";
        command = ''
          jj log 2>/dev/null --no-graph --ignore-working-copy --color=always --revisions @ \
            --template '
              surround(
                "(",
                ")",
                separate(
                  " ",
                  bookmarks.join(", "),
                  change_id.shortest(),
                  commit_id.shortest(),
                  if(conflict, label("conflict", "×")),
                  if(divergent, label("divergent", "??")),
                  if(hidden, label("hidden prefix", "(hidden)")),
                  if(immutable, label("node immutable", "◆")),
                  coalesce(
                    if(
                      empty,
                      coalesce(
                        if(
                            parents.len() > 1,
                            label("empty", "(merged)"),
                        ),
                        label("empty", "(empty)"),
                      ),
                    ),
                    label("description placeholder", "*")
                  ),
                )
              )
            '
        '';
      };
    };
  };
}
