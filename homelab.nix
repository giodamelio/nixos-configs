{
  networking = {
    carbon = {
      primaryInterface = "eno1";
      interfaces = {
        eno1 = {
          address = "10.30.0.10";
          prefixLength = 24;
          gateway = "10.30.0.1";
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
