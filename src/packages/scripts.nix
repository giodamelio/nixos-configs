{
  debug,
  inputs,
  ...
}: {pkgs}: let
  # Create a copy of our nixpkgs with the Nu builder
  pkgsWithNu = import inputs.nixpkgs {
    inherit (pkgs) system;
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
  zdeploy = pkgsWithNu.nuenv.mkCommand {
    name = "zdeploy";
    runtimeInputs = with pkgsWithNu; [zellij];
    args = ["host:string"];
    description = "Run deploy command in another Zellij session (that I keep open on another monitor)";
    text = ''
      # Write ASCII ETX (end of text), basically ^C
      zellij --session runner action write 3
      zellij --session runner action write-chars "deploy "
      zellij --session runner action write-chars $host
      # Write ASCII Newline
      zellij --session runner action write 10
    '';
  };
  deploy = pkgsWithNu.nuenv.mkCommand {
    name = "deploy";
    description = "Interactivaly choose a host and deploy to it";
    runtimeInputs = with pkgsWithNu; [skim];
    args = ["host?:string"];
    flags = {
      verbose = {
        description = "Disable Colmena spinners and print the whole build log";
        type = "bool";
        short = "v";
      };
    };
    text = ''
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
        colmena apply --verbose --on $node
      } else {
        colmena apply --on $node
      }
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
