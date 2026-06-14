# Throwaway: proves runDenNixOSTest boots real den hosts.
_: {
  perSystem.denTests.den-harness-spike = {
    fleet = _: {
      den.hosts.x86_64-linux.alpha = {};
      den.hosts.x86_64-linux.beta = {};

      # Reading host.name proves den resolved the host, not a plain module.
      den.aspects.alpha.nixos = {host, ...}: {
        system.stateVersion = "25.11";
        environment.etc."den-host".text = host.name;
      };
      den.aspects.beta.nixos = {host, ...}: {
        system.stateVersion = "25.11";
        environment.etc."den-host".text = host.name;
      };
    };

    nodes = {
      alpha = "alpha";
      beta = "beta";
    };

    testScript = ''
      start_all()
      alpha.wait_for_unit("multi-user.target")
      beta.wait_for_unit("multi-user.target")

      with subtest("den rendered the host context onto each node"):
          assert alpha.succeed("cat /etc/den-host").strip() == "alpha"
          assert beta.succeed("cat /etc/den-host").strip() == "beta"

      with subtest("nodes reach each other over the test network"):
          alpha.succeed("ping -c1 beta")
          beta.succeed("ping -c1 alpha")
    '';
  };
}
