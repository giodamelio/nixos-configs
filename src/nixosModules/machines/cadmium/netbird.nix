_: {pkgs, ...}: {
  environment.systemPackages = [pkgs.dogdns];

  services.netbird = {
    enable = true;

    tunnels.main = {};
  };
}
