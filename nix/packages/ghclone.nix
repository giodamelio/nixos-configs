{
  flake,
  pkgs,
  ...
}:
flake.lib.writeNushellApplication pkgs {
  name = "ghclone";
  runtimeInputs = with pkgs; [git];
  source = ''
    # Clone a GitHub repo into ~/projects/<owner>/<repo>
    def main [
      input: string  # owner/repo, https://github.com/owner/repo, or git@github.com:owner/repo
    ] {
      let parsed = if ($input | str starts-with "https://github.com/") {
        $input | str replace "https://github.com/" "" | str replace ".git" "" | split row "/"
      } else if ($input | str starts-with "git@github.com:") {
        $input | str replace "git@github.com:" "" | str replace ".git" "" | split row "/"
      } else if ($input =~ '^[^/]+/[^/]+$') {
        $input | split row "/"
      } else {
        print "Invalid format. Use: owner/repo, https://github.com/owner/repo, or git@github.com:owner/repo"
        exit 1
      }

      let owner = $parsed.0
      let repo = $parsed.1
      let projects_dir = $"($env.HOME)/projects"
      let owner_dir = $"($projects_dir)/($owner)"
      let repo_dir = $"($owner_dir)/($repo)"

      if ($repo_dir | path exists) {
        print $"Repository already exists at ($repo_dir)"
        exit 1
      }

      mkdir $owner_dir
      git clone $"https://github.com/($owner)/($repo).git" $repo_dir
      print $"Cloned to ($repo_dir)"
    }
  '';
}
