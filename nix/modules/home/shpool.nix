{config, ...}: {
  services.shpool = {
    enable = config.gio.role == "server";
    settings = {
      session_restore_mode = {
        lines = 1000;
      };
    };
  };
}
