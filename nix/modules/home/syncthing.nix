{pkgs, ...}: {
  services.syncthing = {
    enable = true;
    tray.enable = true;
  };

  systemd.user.services.syncthingtray.Service.ExecStart =
    pkgs.lib.mkForce
    "${pkgs.syncthingtray-minimal}/bin/syncthingtray --wait";
}
