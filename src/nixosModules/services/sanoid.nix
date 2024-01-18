_: {pkgs, ...}: {
  services.sanoid = {
    enable = true;

    datasets."tank/home" = {
      hourly = 48;
      daily = 32;
      monthly = 8;
      yearly = 8;

      autosnap = true;
      autoprune = true;
    };
  };
}
