{pkgs, ...}: {
  environment.systemPackages = with pkgs; [pgcli];

  services.postgresql = {
    enable = true;
  };
}
