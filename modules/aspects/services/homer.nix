{
  lib,
  config,
  ...
}: let
  inherit (import ./_types.nix {inherit lib;}) homerServicesOf;
  denHosts = lib.concatMapAttrs (_system: hosts: hosts) config.den.hosts;
in {
  # Renders the Homer dashboard from every service's dashboard facet (grouped by
  # category). Self-gates on host.homer.enable. Homer has no daemon — it's a static
  # site (pkgs.homer) served through the Caddy reverse-proxy layer with a generated
  # config.yml. Non-service tiles go through fleet.homer.extraServices.
  den.aspects.services-homer.nixos = {
    host,
    fleet,
    lib,
    pkgs,
    ...
  }: let
    settings = {
      inherit (fleet.homer) title subtitle;
      services = homerServicesOf denHosts ++ fleet.homer.extraServices;
    };
    configFile = (pkgs.formats.yaml {}).generate "homer-config.yml" settings;
  in
    lib.mkIf host.homer.enable {
      services.gio.reverse-proxy = {
        enable = true;
        virtualHosts.homer = {
          reverseProxy = false;
          extraConfig = ''
            root * ${pkgs.homer}
            file_server
            handle_path /assets/config.yml {
              root * ${configFile}
              file_server
            }
          '';
        };
      };
    };
}
