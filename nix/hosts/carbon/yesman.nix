_: {
  gio.deployedApps.yesman = {
    description = "Yesman test app (socket-activated)";
    listener.type = "unix-activated";
    # The reverse proxy is declared by hand below (instead of via this facet) so
    # the Caddy vhost can speak h2c to the socket — see the comment on the vhost.
    reverseProxy.enable = false;
    # Managed by the gradient-deployer agent: it pulls the latest succeeded
    # build of this Gradient project and deploys it on webhook.
    gradient.project = "default/yesman";
  };

  # yesman serves a Restate SDK at /restate alongside its plain HTTP routes, all
  # on the same Unix socket. Caddy must reach that backend over HTTP/2 cleartext:
  # Restate's invoke path is bidirectional-streaming and falls apart over HTTP/1.1.
  # Caddy's default upstream protocol is HTTP/1.1, so we force h2c on the
  # transport. The app multiplexes h2c and HTTP/1.1 on the socket, so the plain
  # / and /random routes keep working too.
  #
  # `reverseProxy = false` suppresses the module's auto `reverse_proxy` directive
  # so this transport-carrying one is the only one. Because we bypassed the
  # deployedApps reverse-proxy facet, we also re-add Caddy to the yesman group
  # (below) so it can read the 0660 socket.
  services.gio.reverse-proxy.virtualHosts.yesman = {
    socket_path = "/run/yesman/yesman.sock";
    reverseProxy = false;
    extraConfig = ''
      reverse_proxy unix//run/yesman/yesman.sock {
        transport http {
          versions h2c
        }
      }
    '';
  };

  users.users.caddy.extraGroups = ["yesman"];

  # Register yesman's Restate SDK endpoint so the local Restate server discovers
  # its handlers (the Random virtual object). Restate reaches it through the
  # public Caddy vhost over h2-over-TLS; the /restate prefix is the SDK's mount
  # point (the SDK routes on RequestURI). The local Restate runtime resolves
  # yesman.gio.ninja to the local Caddy. Registration is a --force oneshot that
  # waits for the admin API and retries, so it tolerates yesman being
  # socket-activated (the register call itself wakes the socket).
  #
  # NOTE: a new Gradient deploy that changes handlers is applied out-of-band (the
  # gradient-deployer agent swaps the profile + restarts the unit), so it does
  # not re-trigger this oneshot. Re-run registration after such a deploy if the
  # handler surface changed.
  gio.restate.deployments.yesman = {
    endpoint = "https://yesman.gio.ninja/restate";
    dependencies = ["yesman.socket" "caddy.service"];
  };
}
