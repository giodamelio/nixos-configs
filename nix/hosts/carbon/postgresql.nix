{pkgs, ...}: {
  environment.systemPackages = with pkgs; [pgcli];

  services.postgresql = {
    enable = true;
  };

  services.prometheus.exporters.postgres = {
    enable = true;
    listenAddress = "127.0.0.1";
    runAsLocalSuperUser = true;
  };
}
