{lib, ...}: let
  inherit (import ./_types.nix {inherit lib;}) accessToType identityOptions;
in {
  den.schema.host.imports = [
    {
      options.ssh = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = ''
            false = this host does not exist as far as the SSH system is
            concerned: never a sign target (hostKey may stay unset), no cert
            trust or grant config on the host, not a valid grant target, its
            users grant nothing. For hosts that aren't deployed yet.
          '';
        };
        # No default: enabled hosts must set this, even if explicitly null.
        hostKey = lib.mkOption {
          type = lib.types.nullOr lib.types.singleLineStr;
          description = ''
            The host's ed25519 public host key, signed by the SSH CA into this
            host's certificate. Obtain with: ssh-keyscan -t ed25519 <host>
            (cross-check against /etc/ssh/ssh_host_ed25519_key.pub on the
            console). Explicit null = not enrolled yet.
          '';
        };
        extraPrincipals = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [];
          description = ''
            Extra certificate principals beyond "<host>" and
            "<host>.gio.ninja" (vanity names, IPs).
          '';
        };
      };
    }
  ];

  den.schema.user.imports = [
    {
      options.ssh = {
        publicKey = lib.mkOption {
          type = lib.types.nullOr lib.types.singleLineStr;
          default = null;
          description = "This user-on-this-host's ed25519 pubkey (for grants/user certs).";
        };
        accessTo = lib.mkOption {
          type = accessToType;
          default = {};
          description = "Access grants: ssh.accessTo.<toHost>.<toUser> = true.";
        };
      };
    }
  ];

  den.schema.fleet.imports = [
    {
      options.ssh = {
        externalClients = lib.mkOption {
          type = lib.types.attrsOf (lib.types.submodule {options = identityOptions;});
          default = {};
          description = ''
            SSH clients with access grants but no managed config (phone,
            tablet). Grant sources only; they get user certs signed by the CA
            and/or authorized_keys entries from their accessTo.
          '';
        };
        revocations = {
          users = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            default = [];
            description = ''
              ssh-keygen KRL spec lines revoking user certs/keys fleet-wide
              (enforced by sshd RevokedKeys). e.g. "id: termius-phone",
              "serial: 123456", "key: ssh-ed25519 AAAA…".
            '';
          };
          hosts = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            default = [];
            description = ''
              KRL spec lines revoking host certs fleet-wide (enforced by ssh
              client RevokedHostKeys).
            '';
          };
        };
      };
    }
  ];
}
