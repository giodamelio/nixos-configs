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

    def herdr-reporting [] {
      (
        ($env.HERDR_PANE_ID? | is-not-empty)
        and ($env.HERDR_SOCKET_PATH? | is-not-empty)
        and (($env.HERDR_SOCKET_PATH | path type) == "socket")
        and (which herdr | is-not-empty)
      )
    }

    # herdr drops reports without a seq once a source has sent one
    def report-deploy [reporting: bool, state: string, message: string] {
      if not $reporting { return }
      (herdr pane report-agent $env.HERDR_PANE_ID
        --source local:deploy --agent "NixOS deploy"
        --state $state --message $message --seq (date now | into int))
        | ignore
    }

    # Keep the final status visible in herdr until acknowledged
    def finish-deploy [reporting: bool, message: string] {
      if not $reporting { return }
      report-deploy $reporting idle $message
      print "Press any key to clear the herdr status"
      input listen --types [key] | ignore
      (herdr pane release-agent $env.HERDR_PANE_ID
        --source local:deploy --agent "NixOS deploy"
        --seq (date now | into int))
        | ignore
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
      let reporting = (herdr-reporting)

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

      # A per-run GC root instead of ./result, so parallel deploys don't fight
      # over one link.
      let gcroot_dir = (mktemp -d -t $'deploy-($host).XXXXXX')
      let gcroot = $'($gcroot_dir)/result'

      try {
        # Build the OS first
        report-deploy $reporting working $'building ($host)'
        nh os build --diff never --out-link $gcroot $".#nixosConfigurations.($host)"
        let system = ($gcroot | path expand)
        print $'built ($system)'

        # Push it to the binary cache
        # attic push homelab $system

        # Then actually deploy it
        report-deploy $reporting working $'switching ($host)'
        # The built path, not the flake: what activates is exactly what was
        # built, even if the tree changes mid-deploy.
        if $is_local_deploy {
          nh os switch --ask ...$args $system
        } else {
          nh os switch --ask ...$args --target-host $destination $system
        }

        rm -r $gcroot_dir
      } catch {|err|
        rm -r $gcroot_dir
        print -e $err.rendered
        finish-deploy $reporting $'failed ($host)'
        exit 1
      }

      finish-deploy $reporting $'deployed ($host)'
    }
  '';
}
