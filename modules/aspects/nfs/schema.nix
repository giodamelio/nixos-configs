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
          description = ''
            Take part in fleet NFS over TLS: run tlshd and keep a step-ca
            certificate (enrolled once with `ca-enroll-host <host> nfs`).
          '';
        };
      };
    }
  ];

  den.schema.fleet.imports = [
    ({config, ...}: {
      options.nfs = {
        caRoot = mkOption {
          type = types.path;
          default = config.ssh.dataDir + "/ca-root.crt";
          defaultText = lib.literalExpression "fleet.ssh.dataDir + \"/ca-root.crt\"";
          description = ''
            step-ca root certificate: the tlshd truststore and the `--root` for
            enrollment and renewal. Tests point it at a throwaway CA.
          '';
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
    })
  ];
}
