{lib, ...}: let
  inherit (lib) mkOption types;
in {
  den.schema.host.imports = [
    {
      options.homer.enable = mkOption {
        type = types.bool;
        default = false;
        description = "Serve the Homer dashboard on this host, rendered from every service's dashboard facet.";
      };
    }
  ];

  den.schema.fleet.imports = [
    {
      options.homer = {
        title = mkOption {
          type = types.str;
          default = "Homelab";
          description = "Dashboard title.";
        };
        subtitle = mkOption {
          type = types.str;
          default = "";
          description = "Dashboard subtitle.";
        };
        extraServices = mkOption {
          type = types.listOf (types.attrsOf types.anything);
          default = [];
          description = ''
            Raw Homer service groups appended to the rendered ones — escape hatch
            for tiles that aren't fleet services (external tools, admin links).
          '';
        };
      };
    }
  ];
}
