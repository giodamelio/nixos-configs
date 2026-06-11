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
  prek = pkgs: flake: let
    remind-me-to = inputs.giopkgs.packages.${pkgs.stdenv.hostPlatform.system}.remind-me-to;
  in
    import ./prek.nix {
      inherit pkgs remind-me-to;
      inherit (flake.packages.${pkgs.stdenv.hostPlatform.system}) check-drv-drift;
      treefmt = flake.lib.treefmt pkgs;
    };

  writeNushellApplication = pkgs: {
    name,
    source,
    runtimeInputs ? [],
    meta ? {},
    passthru ? {},
    # Forward process stdin to main's pipeline input ($in); without it $in is
    # nothing in scripts. https://www.nushell.sh/book/scripts.html#subcommands
    stdin ? false,
  }: let
    inherit (pkgs) lib;
  in
    pkgs.writeTextFile {
      inherit name meta passthru;
      executable = true;
      destination = "/bin/${name}";
      text =
        ''
          #!${pkgs.nushell}/bin/nu${lib.optionalString stdin " --stdin"}

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
