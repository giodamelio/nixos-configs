{
  config,
  lib,
  ...
}: let
  data = import ../../../../homelab.nix;
  cfg = config.gio.homelab;
in {
  imports = [
    ./static-network.nix
  ];

  options.gio.homelab = {
    networking = lib.mkOption {
      type = lib.types.attrsOf (lib.types.submodule {
        options = {
          primaryInterface = lib.mkOption {
            type = lib.types.str;
            description = "Name of the primary network interface for this host";
          };
          interfaces = lib.mkOption {
            type = lib.types.attrsOf (lib.types.submodule {
              options = {
                address = lib.mkOption {
                  type = lib.types.str;
                  description = "Static IPv4 address";
                };
                prefixLength = lib.mkOption {
                  type = lib.types.int;
                  description = "Network prefix length";
                };
                gateway = lib.mkOption {
                  type = lib.types.str;
                  description = "Default gateway address";
                };
              };
            });
            description = "Per-interface static network configuration";
          };
        };
      });
      default = {};
      description = "Per-host networking configuration keyed by hostname";
    };

    nfs = {
      peers = lib.mkOption {
        type = lib.types.attrsOf (lib.types.submodule {
          options = {
            wgIp = lib.mkOption {
              type = lib.types.str;
              description = "WireGuard IP address for the NFS mesh";
            };
            wgPublicKey = lib.mkOption {
              type = lib.types.str;
              default = "";
              description = "WireGuard public key";
            };
          };
        });
        default = {};
        description = "WireGuard NFS mesh peer definitions keyed by hostname";
      };

      shares = lib.mkOption {
        type = lib.types.attrsOf (lib.types.submodule {
          options = {
            source = {
              host = lib.mkOption {
                type = lib.types.str;
                description = "Hostname of the NFS server";
              };
              path = lib.mkOption {
                type = lib.types.str;
                description = "Path on the source host";
              };
            };
            mounts = lib.mkOption {
              type = lib.types.attrsOf (lib.types.submodule {
                options = {
                  path = lib.mkOption {
                    type = lib.types.str;
                    description = "Mount point on the client host";
                  };
                  readOnly = lib.mkOption {
                    type = lib.types.bool;
                    default = false;
                    description = "Whether to mount read-only";
                  };
                };
              });
              default = {};
              description = "Mount definitions keyed by client hostname";
            };
          };
        });
        default = {};
        description = "NFS share definitions";
      };
    };
  };

  config = {
    gio.homelab = data;

    assertions =
      lib.mapAttrsToList (hostname: hostCfg: {
        assertion = hostCfg.interfaces ? ${hostCfg.primaryInterface};
        message = "homelab: ${hostname}'s primaryInterface '${hostCfg.primaryInterface}' is not in its interfaces";
      })
      cfg.networking;
  };
}
