{lib, ...}: let
  inherit (lib) mkOption types;

  # Fluent chain: mounts.<name>.<serverHost>.<serverPath>.<clientHost>.<clientPath>.
  # The path levels carry an override `path` option (defaulting to the key) — done
  # via a strictly-typed freeformType catch-all, NOT loose freeform.
  clientPath = types.submodule ({name, ...}: {
    options = {
      path = mkOption {
        type = types.str;
        default = name;
        defaultText = lib.literalExpression "<the client-path key>";
        description = "Client mount path; defaults to the attribute key.";
      };
      enable = mkOption {
        type = types.bool;
        default = true;
        description = "Whether this mount is active.";
      };
      readOnly = mkOption {
        type = types.bool;
        default = false;
        description = "Mount read-only.";
      };
    };
  });

  serverPath = types.submodule ({name, ...}: {
    options.path = mkOption {
      type = types.str;
      default = name;
      defaultText = lib.literalExpression "<the server-path key>";
      description = "Server export path; defaults to the attribute key.";
    };
    # Any non-`path` key is a <clientHost>, each holding <clientPath> entries.
    freeformType = types.attrsOf (types.attrsOf clientPath);
  });
in {
  den.schema.host.imports = [
    {
      options.nfs = {
        enable = mkOption {
          type = types.bool;
          default = false;
          description = "Participate in the fleet NFS + WireGuard mesh.";
        };
        wgIp = mkOption {
          type = types.nullOr types.str;
          default = null;
          description = "This host's WireGuard mesh IP (explicit; never auto-allocated).";
        };
        endpoint = mkOption {
          type = types.nullOr types.str;
          default = null;
          defaultText = lib.literalExpression "<host name>";
          description = "Address peers dial for the tunnel (LAN IP / FQDN). Defaults to the host name.";
        };
      };
    }
  ];

  den.schema.fleet.imports = [
    {
      options.nfs = {
        network = {
          interface = mkOption {
            type = types.str;
            default = "wg-nfs";
            description = "WireGuard interface name.";
          };
          port = mkOption {
            type = types.int;
            default = 51830;
            description = "WireGuard listen port.";
          };
          subnet = mkOption {
            type = types.str;
            default = "10.200.0.0/24";
            description = "WireGuard mesh subnet (used for the export ACL).";
          };
        };
        mounts = mkOption {
          default = {};
          description = ''
            NFS mounts as a fluent chain:
            mounts.<name>.<serverHost>.<serverPath>.<clientHost>.<clientPath>.
            Path keys may be overridden by a `path` option at their own level
            (for unwieldy paths), and `enable`/`readOnly` live on the client leaf.
            One name may fan a server export out to many clients; definitions
            merge across files. The host that a service waits on is nfs-<name>.target.
          '';
          type = types.attrsOf (types.attrsOf (types.attrsOf serverPath));
        };
      };
    }
  ];
}
