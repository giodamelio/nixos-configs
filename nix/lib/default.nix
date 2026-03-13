{inputs, ...}: {
  homelab = builtins.fromTOML (builtins.readFile ../../homelab.toml);

  # Loaded up version of treefmt that has all the things available on it
  treefmt = pkgs: let
    treefmtConfig = pkgs:
      import ../../treefmt.nix {
        inherit pkgs;
        inherit (inputs.treefmt-nix.lib) evalModule;
      };
  in
    (treefmtConfig pkgs).config.build;

  # Prek hooks configuration and shell integration
  prek = pkgs: flake:
    import ./prek.nix {
      inherit pkgs;
      treefmt = flake.lib.treefmt pkgs;
    };

  writeNushellApplication = pkgs: {
    name,
    source,
    runtimeInputs ? [],
    meta ? {},
  }: let
    inherit (pkgs) lib;
  in
    pkgs.writeTextFile {
      inherit name meta;
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
