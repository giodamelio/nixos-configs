{ pkgs, lib, config, ... }: {
  programs.git = {
    enable = true;
    userName = "Giovanni d'Amelio";
    userEmail = "gio@damelio.net";
    aliases = {
      ci = "commit";
      st = "status";
    };
    delta = {
      enable = true;
    };
  };
}
