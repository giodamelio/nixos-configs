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
  z = pkgsWithNu.nuenv.mkCommand {
    name = "z";
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
}
