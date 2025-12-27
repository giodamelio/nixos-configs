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
      let local_hostname = (hostname | str trim)
      let is_local_deploy = ($host == $local_hostname)

      if $is_local_deploy {
        print $'Deploying to ($host) locally...'
      } else {
        print $'Deploying to ($host) at ($destination)...'
      }
      print ""

      # if ($verbose != null) {
      #   colmena apply --verbose --on $node --experimental-flake-eval
      # } else {
      #   colmena apply --on $node --experimental-flake-eval
      # }

      # Build the OS first
      nh os build --diff never $".#nixosConfigurations.($host)"

      # Push it to the binary cache
      attic push homelab result/

      # Then actually deploy it
      if $is_local_deploy {
        nh os switch --ask ...$args --hostname $host .
      } else {
        nh os switch --ask ...$args --hostname $host --target-host $destination .
      }

      # Clean up the result so the changes don't look so crazy
      rm result
    }
  '';
}
