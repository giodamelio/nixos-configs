# yesman — Restate SDK test app, a gradient-deployed socket-activated app slot.
# Caddy speaks h2c to its unix socket (Restate's invoke path is bidi-streaming and
# breaks over HTTP/1.1); the fleet endpoint renders that transport. Caddy joins
# the yesman group to read the 0660 socket. Its Restate SDK endpoint is registered
# via gio.restate.deployments. No consul (matches Blueprint). Converted from
# nix/hosts/carbon/yesman.nix.
_: {
  den.aspects.carbon.nixos = {
    gio.deployedApps.yesman = {
      description = "Yesman test app (socket-activated)";
      listener.type = "unix-activated";
      reverseProxy.enable = false; # h2c vhost via fleet.services below
      gradient.project = "default/yesman";
    };

    # The deployed-apps aspect only adds caddy to the app group for its own
    # reverse-proxy facet; we render the vhost ourselves, so add it here.
    users.users.caddy.extraGroups = ["yesman"];

    gio.restate.deployments.yesman = {
      endpoint = "https://yesman.gio.ninja/restate";
      dependencies = ["yesman.socket" "caddy.service"];
    };
  };

  den.hosts.x86_64-linux.carbon.services.yesman = {
    endpoint = {
      domain = "yesman";
      backend.socket = "/run/yesman/yesman.sock";
      backend.protocol = "h2c";
    };
    consul.enable = false;
  };
}
