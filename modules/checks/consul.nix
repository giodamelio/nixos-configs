# Boots a single-node Consul host and proves the cluster + registration render
# path end to end under ACL deny: the agent forms, an on-by-default service lands
# in the catalog, `consul.enable = false` opts a service out, a check derived
# from the healthcheck facet is registered and passing, and anonymous requests
# see nothing. The gossip key and ACL tokens are plaintext credentials standing
# in for the agevault-encrypted blobs, and the manifest is stubbed so the
# fleet.credentials assertion is satisfied.
_: let
  # Fixed test-only values. The agent token doubles as initial_management so the
  # test needs no `consul acl bootstrap` step.
  token = "3bedfa82-175d-4b42-8e90-67fdbd3f1645";
  gossipKey = "BLA6sMz8r34hBj+te15YGWHbyTpM43Ey3yorD9rtQ10=";
in {
  perSystem.denTests.consul = {
    fleet = _: {
      den.hosts.x86_64-linux.srv = {
        ssh.hostKey = null;
        consul.enable = true;
        # eth0 is the VM's primary NIC; static-network gives it this address and
        # consul binds to it (theInterface). A real device (not lo) is required —
        # consul's unit waits on sys-subsystem-net-devices-<iface>.device.
        network.interfaces.eth0.address = "10.99.0.1";
        services = {
          # On by default. A tcp check at consul's own port, so it actually passes.
          demo.healthcheck = {
            protocol = "tcp";
            target = "127.0.0.1:8500";
          };
          # Opted out of Consul registration.
          skip = {
            consul.enable = false;
            healthcheck = {
              protocol = "tcp";
              target = "127.0.0.1:8500";
            };
          };
        };
      };

      den.aspects.srv.nixos = {
        lib,
        pkgs,
        ...
      }: {
        system.stateVersion = "25.11";
        nixpkgs.config.allowUnfree = true; # consul is unfree (HashiCorp BSL)
        environment.systemPackages = [pkgs.consul];
        networking.nftables.enable = true;

        fleet.credentials.manifestFile = builtins.toFile "manifest.toml" ''
          srv = ["consul_encrypt", "consul_acl_tokens"]
        '';

        environment.etc."test-consul-encrypt".text = builtins.toJSON {encrypt = gossipKey;};
        environment.etc."test-consul-acl-tokens".text = builtins.toJSON {
          acl.tokens = {
            initial_management = token;
            agent = token;
            config_file_service_registration = token;
          };
        };
        systemd.services.consul.serviceConfig = {
          LoadCredentialEncrypted = lib.mkForce [];
          LoadCredential = [
            "consul_encrypt:/etc/test-consul-encrypt"
            "consul_acl_tokens:/etc/test-consul-acl-tokens"
          ];
        };
      };
    };

    nodes.srv = "srv";
    node = _: {pkgs, ...}: {environment.systemPackages = [pkgs.jq pkgs.curl];};

    testScript = ''
      auth = "CONSUL_HTTP_TOKEN=${token} "

      srv.start()
      srv.wait_for_unit("consul.service")
      srv.wait_for_open_port(8500)
      srv.wait_until_succeeds(auth + "consul members | grep -qw srv")

      with subtest("on-by-default service is registered in the catalog"):
          srv.wait_until_succeeds(auth + "consul catalog services | grep -qx demo")

      with subtest("consul.enable = false opts a service out"):
          srv.fail(auth + "consul catalog services | grep -qx skip")

      with subtest("the check derived from the healthcheck facet is registered and passing"):
          srv.wait_until_succeeds(
              "curl -sf -H 'X-Consul-Token: ${token}' localhost:8500/v1/health/checks/demo"
              + " | jq -e '.[0].Status == \"passing\"'"
          )

      with subtest("ACL deny hides the catalog from anonymous requests"):
          srv.fail("consul catalog services | grep -qx demo")
          srv.succeed("curl -sf localhost:8500/v1/health/checks/demo | jq -e 'length == 0'")
    '';
  };
}
