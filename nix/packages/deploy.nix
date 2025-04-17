{
  flake,
  pkgs,
  ...
}:
flake.lib.writeNushellApplication pkgs {
  name = "deploy";
  runtimeInputs = [pkgs.skim];
  source = ''
    def hosts [] {
      nix eval .#nixosConfigurations --apply builtins.attrNames --json | from json
    }

    # Deploy all hosts
    def "main all" [] {
      colmena apply
    }

    # Interactivaly choose a host and deploy to it
    def "main" [
      host?: string@hosts
      --verbose (-v) # Disable Colmena spinners and print the whole build log
    ] {
      # If no node is passed, interactivaly pick one
      let node = (if ($host == null) {
        let nodes = (
          nix eval .#nixosConfigurations --apply builtins.attrNames --json
        )
        ($nodes | from json | to text | sk)
      } else {
        $host
      })

      printf "Running 'colmena apply --on %s'\n\n" $node
      if ($verbose != null) {
        colmena apply --verbose --on $node --experimental-flake-eval
      } else {
        colmena apply --on $node --experimental-flake-eval
      }
    }
  '';
}
