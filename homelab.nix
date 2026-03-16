{
  nfs = {
    peers = {
      gallium = {
        wgIp = "10.100.0.1";
        wgPublicKey = "YMsduGtNNbhNbBpl6hkYTfMXWdQn7Xz7KrwRwojEVGE=";
      };
      carbon = {
        wgIp = "10.100.0.2";
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
