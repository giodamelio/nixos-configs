{
  flake,
  pkgs,
  ...
}:
flake.lib.writeNushellApplication pkgs {
  name = "deploy";
  runtimeInputs = with pkgs; [nh];
  source = ''
    def destinations [] {
      let repo_root = (git rev-parse --show-toplevel)
      cat $'($repo_root)/homelab.toml'
        | from toml
        | get machines
        | transpose hostname data
        | where $it.data.deploy?.sshDestination? != null
        | each {|item| [$item.hostname, $item.data.deploy.sshDestination] }
        | into record
    }

    def hosts [] {
      destinations | columns
    }

    # Interactivaly choose a host and deploy to it
    def --wrapped "main" [
      host: string@hosts
      ...args
    ] {
      if $host not-in (hosts) {
        print $'host ($host) not found in (hosts)'
        exit 1
      }
      let destination = (destinations | get $host)
      print $'Deploying to ($host) at ($destination)...'
      print ""

      # if ($verbose != null) {
      #   colmena apply --verbose --on $node --experimental-flake-eval
      # } else {
      #   colmena apply --on $node --experimental-flake-eval
      # }

      nh os switch ...$args --hostname $host --target-host $destination .
    }
  '';
}
