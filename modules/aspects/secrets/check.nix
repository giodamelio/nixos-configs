# Eval-time unit tests for the fleet.secrets inversion/emission helpers in
# _lib.nix — the bug-prone core (credential-directive table, copy-set
# derivation, name handling). Runtime transport is covered by the credsync VM
# test; the full per-host expansion is exercised by building real den hosts.
{lib, ...}: let
  l = import ./_lib.nix {inherit lib;};

  # Minimal stand-ins matching the attrs the helpers actually read.
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

  expect = name: actual: expected:
    if actual == expected
    then true
    else throw "fleet-secrets-lib: ${name}: got ${builtins.toJSON actual}, want ${builtins.toJSON expected}";

  cases = [
    # --- credentialDirective emission table ---
    (expect "directive/default" (l.credentialDirective "foo" (site {})) "LoadCredentialEncrypted=foo")
    (expect "directive/rename" (l.credentialDirective "foo" (site {credential.name = "alias";})) "LoadCredentialEncrypted=alias:foo")
    (expect "directive/source" (l.credentialDirective "foo" (site {
      credential = {
        name = "alias";
        source = "other-blob";
      };
    })) "LoadCredentialEncrypted=alias:other-blob")
    (expect "directive/plain+source" (l.credentialDirective "foo" (site {
      credential = {
        name = "alias";
        source = "/run/x.sock";
        encrypted = false;
      };
    })) "LoadCredential=alias:/run/x.sock")
    (expect "directive/plain+source-noname" (l.credentialDirective "foo" (site {
      credential = {
        source = "/p";
        encrypted = false;
      };
    })) "LoadCredential=foo:/p")

    # --- credentialId / sitePath ---
    (expect "credId/default" (l.credentialId "foo" (site {})) "foo")
    (expect "credId/override" (l.credentialId "foo" (site {credential.name = "bar";})) "bar")
    (expect "sitePath/default" (l.sitePath "foo" (site {unit = "svc";})) "/run/credentials/svc.service/foo")
    (expect "sitePath/rename" (l.sitePath "foo" (site {
      unit = "svc";
      credential.name = "bar";
    })) "/run/credentials/svc.service/bar")

    # --- copySet: enabled use-hosts minus origin, ∪ copyTo ---
    (expect "copySet"
      (l.copySet {
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
      })
      ["b" "c"])

    # --- holdsSecret ---
    (expect "holds/origin" (l.holdsSecret {
        origin = "a";
        copyTo = [];
        use = {};
      } "a")
      true)
    (expect "holds/copy" (l.holdsSecret {
        origin = "a";
        copyTo = ["x"];
        use = {};
      } "x")
      true)
    (expect "holds/none" (l.holdsSecret {
        origin = "a";
        copyTo = [];
        use = {};
      } "z")
      false)

    # --- screamingSnake / validName ---
    (expect "snake" (l.screamingSnake "forgejo-runner-token") "FORGEJO_RUNNER_TOKEN")
    (expect "name/ok" (l.validName "foo-bar1") true)
    (expect "name/upper" (l.validName "Foo") false)
    (expect "name/underscore" (l.validName "foo_bar") false)

    # --- enabledSitesOn: honors host- and site-level enable ---
    (expect "sites/names"
      (map (e: e.siteName) (l.enabledSitesOn {
          use.h = useHost {
            keep = site {};
            drop = site {enable = false;};
          };
        }
        "h"))
      ["keep"])
    (expect "sites/host-disabled"
      (l.enabledSitesOn {
        use.h = {
          enable = false;
          services.x = site {};
        };
      } "h")
      [])
  ];
in {
  perSystem = {
    pkgs,
    config,
    lib,
    ...
  }: {
    checks.fleet-secrets-lib = assert builtins.all (x: x) cases;
      pkgs.runCommand "fleet-secrets-lib" {} "echo ok > $out";

    # Two-VM end-to-end test of the aspect's generated units.
    checks.fleet-secrets-vm = pkgs.testers.runNixOSTest (import ./_test.nix {
      inherit pkgs lib;
      credsync = config.packages.credsync;
    });
  };
}
