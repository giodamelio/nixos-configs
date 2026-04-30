{
  config,
  lib,
  pkgs,
  ...
}: {
  services.kdeconnect = {
    enable = true;
    indicator = true;
  };

  # File browsing dependencies for KDE Connect's SFTP feature
  home.packages = with pkgs; [
    sshfs
    fuse
  ];

  # When noctalia is enabled, add the KDE Connect plugin
  programs.noctalia-shell.plugins = lib.mkIf config.programs.noctalia-shell.enable {
    states = {
      kde-connect = {
        enabled = true;
        sourceUrl = "https://github.com/noctalia-dev/noctalia-plugins";
      };
    };
  };
}
