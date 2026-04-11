{inputs, ...}: {
  homelab = builtins.fromTOML (builtins.readFile ../../homelab.toml);

  # Loaded up version of treefmt that has all the things available on it
  treefmt = pkgs: let
    statix-pipe = import ../packages/statix-pipe.nix {inherit pkgs;};
    treefmtConfig = pkgs:
      import ../../treefmt.nix {
        inherit pkgs statix-pipe;
        inherit (inputs.treefmt-nix.lib) evalModule;
      };
  in
    (treefmtConfig pkgs).config.build;

  # Prek hooks configuration and shell integration
  prek = pkgs: flake: let
    statix-pipe = import ../packages/statix-pipe.nix {inherit pkgs;};
    remind-me-to = inputs.giopkgs.packages.${pkgs.stdenv.hostPlatform.system}.remind-me-to;
  in
    import ./prek.nix {
      inherit pkgs statix-pipe remind-me-to;
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
