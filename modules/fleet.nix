{
  lib,
  config,
  den,
  ...
}: {
  options.fleet = lib.mkOption {
    description = ''
      Fleet-wide facts, evaluated against den.schema.fleet (declare option
      types there; set values here). Consumed by aspects via the `fleet`
      context arg.
    '';
    type = lib.types.submoduleWith {
      shorthandOnlyDefinesConfig = true;
      modules = [config.den.schema.fleet];
    };
    default = {};
  };

  config = {
    den.schema.fleet.imports = [
      {
        options.name = lib.mkOption {
          type = lib.types.str;
          default = "homelab";
          description = "Display name of the fleet.";
        };
      }
    ];

    den.policies.to-fleet = _: [
      (den.lib.policy.resolve.to "fleet" {inherit (config) fleet;})
    ];

    # Verbatim body of den's built-in flake-to-systems, re-homed under the
    # fleet scope so everything below receives the `fleet` context arg.
    den.policies.fleet-to-systems = _:
      map (system: den.lib.policy.resolve.to "flake-system" {inherit system;}) den.systems;

    den.schema.flake = {
      excludes = [den.policies.flake-to-systems];
      includes = [den.policies.to-fleet];
    };
    den.schema.fleet.includes = [den.policies.fleet-to-systems];
  };
}
