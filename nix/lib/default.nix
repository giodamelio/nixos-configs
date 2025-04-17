_: {
  writeNushellApplication = pkgs: {
    name,
    source,
    runtimeInputs ? [],
  }: let
    inherit (pkgs) lib;
  in
    pkgs.writeTextFile {
      inherit name;
      executable = true;
      destination = "/bin/${name}";
      text =
        ''
          #!${pkgs.nushell}/bin/nu

        ''
        + lib.optionalString (runtimeInputs != []) ''
          # Set up PATH with runtime inputs
          $env.PATH = [
            ${lib.concatMapStringsSep "\n  " (input: "\"${lib.getBin input}/bin\"") runtimeInputs}
            $env.PATH
          ] | flatten | uniq
        ''
        + ''

          ${source}
        '';
    };
}
