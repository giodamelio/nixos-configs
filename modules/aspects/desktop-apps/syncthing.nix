# syncthing — file sync with tray icon. Converted from
# nix/modules/home/syncthing.nix.
_: {
  den.aspects.syncthing.homeManager = {pkgs, ...}: {
    services.syncthing = {
      enable = true;
      tray.enable = true;
    };

    systemd.user.services.syncthingtray.Service.ExecStart =
      pkgs.lib.mkForce
      "${pkgs.syncthingtray-minimal}/bin/syncthingtray --wait";
  };
}
