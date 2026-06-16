{lib, ...}: let
  inherit (lib) mkOption types;
in {
  den.schema.host.imports = [
    # `config` is the host submodule: mode's default keys off its own interfaces.
    ({config, ...}: {
      options.network = {
        mode = mkOption {
          type = types.enum ["static" "networkmanager" "dhcp" "unmanaged"];
          default =
            if config.network.interfaces != {}
            then "static"
            else "unmanaged";
          defaultText = lib.literalExpression ''interfaces != {} ? "static" : "unmanaged"'';
          description = ''
            How this host gets its L3 networking:
            - static: addresses from `interfaces`, rendered via systemd-networkd.
            - networkmanager / dhcp: dynamic; no fleet-derivable address.
            - unmanaged: this aspect is inert; the host owns its own networking.

            Readers only ever derive from static hosts; dynamic ones contribute no
            address and are skipped (a service on one falls back to a CNAME).
          '';
        };

        # Name-keyed: the key is the NIC matched by systemd-networkd. No "primary"
        # — selection is the reader's job (see _lib: interfacesOf / theInterface).
        interfaces = mkOption {
          default = {};
          description = "Static interfaces keyed by device name. Meaningful only when mode = \"static\".";
          type = types.attrsOf (types.submodule {
            options = {
              address = mkOption {
                type = types.str;
                description = "Address on this interface.";
              };
              prefixLength = mkOption {
                type = types.int;
                default = 24;
                description = "Network prefix length.";
              };
              gateway = mkOption {
                type = types.nullOr types.str;
                default = null;
                description = "Default gateway reachable on this interface, if any.";
              };
            };
          });
        };
      };
    })
  ];
}
