{lib, ...}: let
  l = import ./_lib.nix {inherit lib;};

  site = attrs:
    {
      enable = true;
      unit = "svc";
      type = "credential";
      credential = {
        name = null;
        source = null;
        encrypted = true;
      };
      restartOnChange = false;
      upholds = false;
    }
    // attrs
    // {
      credential =
        {
          name = null;
          source = null;
          encrypted = true;
        }
        // (attrs.credential or {});
    };

  useHost = services: {
    enable = true;
    inherit services;
  };

  t = expr: expected: {inherit expr expected;};
in {
  # Pure eval tests for the fleet.secrets emission helpers in _lib.nix (the
  # bug-prone core). Run with fastest: `fastest --flake .#tests fleet-secrets`.
  # Case names avoid "/" — fastest cannot address slashed attr names.
  flake.tests.fleet-secrets = {
    directive-default = t (l.credentialDirective "foo" (site {})) "LoadCredentialEncrypted=foo";
    directive-rename = t (l.credentialDirective "foo" (site {credential.name = "alias";})) "LoadCredentialEncrypted=alias:foo";
    directive-source = t (l.credentialDirective "foo" (site {
      credential = {
        name = "alias";
        source = "other-blob";
      };
    })) "LoadCredentialEncrypted=alias:other-blob";
    directive-plain-source = t (l.credentialDirective "foo" (site {
      credential = {
        name = "alias";
        source = "/run/x.sock";
        encrypted = false;
      };
    })) "LoadCredential=alias:/run/x.sock";
    directive-plain-source-noname = t (l.credentialDirective "foo" (site {
      credential = {
        source = "/p";
        encrypted = false;
      };
    })) "LoadCredential=foo:/p";

    cred-id-default = t (l.credentialId "foo" (site {})) "foo";
    cred-id-override = t (l.credentialId "foo" (site {credential.name = "bar";})) "bar";
    site-path-default = t (l.sitePath "foo" (site {unit = "svc";})) "/run/credentials/svc.service/foo";
    site-path-rename = t (l.sitePath "foo" (site {
      unit = "svc";
      credential.name = "bar";
    })) "/run/credentials/svc.service/bar";

    copy-set = t (l.copySet {
      origin = "a";
      copyTo = ["c"];
      use = {
        a = useHost {};
        b = useHost {};
        d = {
          enable = false;
          services = {};
        };
      };
    }) ["b" "c"];

    holds-origin =
      t (l.holdsSecret {
        origin = "a";
        copyTo = [];
        use = {};
      } "a")
      true;
    holds-copy =
      t (l.holdsSecret {
        origin = "a";
        copyTo = ["x"];
        use = {};
      } "x")
      true;
    holds-none =
      t (l.holdsSecret {
        origin = "a";
        copyTo = [];
        use = {};
      } "z")
      false;

    snake = t (l.screamingSnake "forgejo-runner-token") "FORGEJO_RUNNER_TOKEN";
    name-ok = t (l.validName "foo-bar1") true;
    name-upper = t (l.validName "Foo") false;
    name-underscore = t (l.validName "foo_bar") false;
    name-dot-rejected = t (l.validName "consul-encrypt.json") false;
    credid-dot-ok = t (l.validCredentialId "consul-encrypt.json") true;
    credid-upper-rejected = t (l.validCredentialId "Foo.json") false;

    sites-names = t (map (e: e.siteName) (l.enabledSitesOn {
      use.h = useHost {
        keep = site {};
        drop = site {enable = false;};
      };
    } "h")) ["keep"];
    sites-host-disabled = t (l.enabledSitesOn {
      use.h = {
        enable = false;
        services.x = site {};
      };
    } "h") [];
  };

  perSystem = {
    pkgs,
    config,
    lib,
    ...
  }: {
    # Two-VM end-to-end test of the aspect's generated units.
    checks.fleet-secrets-vm = pkgs.testers.runNixOSTest (import ./_test.nix {
      inherit pkgs lib;
      credsync = config.packages.credsync;
    });
  };
}
