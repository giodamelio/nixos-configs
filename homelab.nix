{
  networking = {
    carbon = {
      primaryInterface = "eno1";
      interfaces = {
        eno1 = {
          address = "10.30.0.10";
          prefixLength = 24;
          gateway = "10.30.0.1";
          ula = "fd7f:148b:0a27:30::10/64";
          vlans = [
            {
              name = "iot0";
              id = 4;
              subnets = [
                "10.40.0.0/16"
                "2604:5500:70cf:fd00::/64"
              ];
            }
          ];
        };
      };
    };
    gallium = {
      primaryInterface = "enp5s0";
      interfaces = {
        enp5s0 = {
          address = "10.30.0.11";
          prefixLength = 24;
          gateway = "10.30.0.1";
          ula = "fd7f:148b:0a27:30::11/64";
        };
      };
    };
    rhodium = {
      primaryInterface = "eth0";
      interfaces = {
        eth0 = {
          address = "10.30.0.12";
          prefixLength = 24;
          gateway = "10.30.0.1";
        };
      };
    };
  };

  nfs = {
    peers = {
      gallium = {
        wgIp = "10.200.0.1";
        wgPublicKey = "YMsduGtNNbhNbBpl6hkYTfMXWdQn7Xz7KrwRwojEVGE=";
      };
      carbon = {
        wgIp = "10.200.0.2";
        wgPublicKey = "P8wlozMnvqnqb+qo0azgmBFsdX93LpywZ7dV+zI5sjc=";
      };
    };

    shares = {
      forgejo = {
        source = {
          host = "gallium";
          path = "/tank/forgejo";
        };
        mounts.carbon = {
          path = "/mnt/forgejo-repos";
          readOnly = false;
        };
      };

      paperless-ngx = {
        source = {
          host = "gallium";
          path = "/tank/paperless";
        };
        mounts.carbon = {
          path = "/mnt/paperless-media";
          readOnly = false;
        };
      };
    };
  };
}
