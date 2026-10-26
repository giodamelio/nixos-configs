# giodamelio/google-calendar-mcp on carbon's Unison Cloud. It verifies
# X-Bifrost-Assertion itself.
_: {
  den.aspects.carbon.nixos = {
    gio.bifrost.services.google-calendar-mcp = {
      oauth.groups = [];
      config = ''
        # reverse_proxy upstreams can't carry a path, so the prefix is a rewrite.
        rewrite * /services/s/giodamelio/google-calendar-mcp{uri}
        reverse_proxy https://app.unison.gio.ninja
      '';
    };
  };
}
