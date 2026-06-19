# samba on gallium — SMB3 share of the dumping-zone dataset, LAN-only. No HTTP
# endpoint; consul gets an explicit address/port + TCP health check (there's no
# primary endpoint to derive them from). Converted from nix/hosts/gallium/samba.nix.
_: {
  den.aspects.gallium.nixos = {
    services.samba = {
      enable = true;
      openFirewall = false;
      settings = {
        global = {
          "server string" = "Gallium NAS";
          "server role" = "standalone server";

          # Security: SMB3 minimum, no guest access
          "server min protocol" = "SMB3_00";
          "map to guest" = "never";

          # LAN-only access
          "hosts allow" = "10.0.0.0/16 10.30.0.0/24 127.0.0.1";
          "hosts deny" = "0.0.0.0/0";
          interfaces = "enp5s0 lo";
          "bind interfaces only" = "yes";

          # Logging
          logging = "systemd";
          "log level" = "1";
        };

        "hard-drive-dumping-zone" = {
          path = "/tank/hard-drive-dumping-zone";
          "valid users" = "server";
          "read only" = "no";
          browseable = "yes";
          "create mask" = "0664";
          "directory mask" = "0775";
          "force user" = "server";
          "force group" = "users";
        };
      };
    };

    # SMB only on the LAN interface.
    networking.firewall.interfaces."enp5s0".allowedTCPPorts = [445];
  };

  den.hosts.x86_64-linux.gallium.services.samba = {
    consul = {
      address = "10.30.0.11";
      port = 445;
    };
    healthcheck = {
      protocol = "tcp";
      target = "10.30.0.11:445";
    };
  };
}
