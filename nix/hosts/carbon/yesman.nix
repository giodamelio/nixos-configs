_: {
  gio.deployedApps.yesman = {
    description = "Yesman test app (socket-activated)";
    listener.type = "unix-activated";
    reverseProxy = {
      enable = true;
      subdomain = "yesman";
    };
  };
}
