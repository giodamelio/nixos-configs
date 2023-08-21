{
  debug,
  inputs,
  ...
}: {
  pkgs,
  system,
}: let
  # Create a copy of our nixpkgs with the Nu builder
  pkgsWithNu = import inputs.nixpkgs {
    inherit system;
    overlays = [inputs.nuenv.overlays.nuenv];
  };
in {
  zz = pkgsWithNu.nuenv.mkCommand {
    name = "zz";
    runtimeInputs = with pkgsWithNu; [zellij skim];
    description = "Interactivaly choose which Zellij session to join, or create one if none exist";
    text = ''
      let sessions = (zellij list-sessions | lines)
      let session_count = ($sessions | length)
      if $session_count == 0 {
        exec zellij attach --create default
      } else if $session_count == 1 {
        exec zellij attach $sessions.0
      } else {
        let picked_session = ($sessions | to text | sk)
        exec zellij attach $picked_session
      }
    '';
    subCommands = {
      ls = {
        description = "Lists the Zellij sessions";
        text = "zellij ls";
      };
    };
  };
  deploy = pkgsWithNu.nuenv.mkCommand {
    name = "deploy";
    description = "Interactivaly choose a host and deploy to it";
    runtimeInputs = with pkgsWithNu; [skim jq];
    args = ["host?:string"];
    text = ''
      # If there is a host passed, deploy to it
      if ($host != null) {
        colmena apply --on $host
        exit 0
      }

      # Otherwise interactivaly pick a host to deploy to
      let nodes = (
        nix eval .#nixosConfigurations --apply builtins.attrNames --json
      )
      let node = ($nodes | jq  -r ".[]" | sk)

      printf "Running 'colmena apply --on %s'\n\n" $node
      colmena apply --on $node
    '';

    subCommands = {
      all = {
        description = "Deploy all hosts";
        text = ''
          colmena apply
        '';
      };
    };
  };
}
