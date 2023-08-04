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
  oldz = pkgs.writeShellApplication {
    name = "oldz";
    runtimeInputs = with pkgs; [zellij skim];
    text = ''
      zellij list-sessions | sk
    '';
  };
  z = pkgsWithNu.nuenv.mkScript {
    name = "z";
    script = ''
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
  };
}
