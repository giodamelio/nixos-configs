_: {
  gio.deployedApps.yesman = {
    description = "Yesman test app (socket-activated)";
    listener.type = "unix-activated";
    reverseProxy = {
      enable = true;
      subdomain = "yesman";
    };
    # Managed by the gradient-deployer agent: it pulls the latest succeeded
    # build of this Gradient project and deploys it on webhook.
    gradient.project = "default/yesman";
  };
}
