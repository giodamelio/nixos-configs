# giodamelio/hello-world on carbon's Unison Cloud, public at the root of
# hello.external.gio.ninja.
_: {
  den.aspects.carbon.nixos = {
    gio.bifrost.services.hello.config = ''
      # reverse_proxy upstreams can't carry a path, so the prefix is a rewrite.
      rewrite * /services/s/giodamelio/hello-world{uri}
      reverse_proxy https://app.unison.gio.ninja
    '';
  };
}
