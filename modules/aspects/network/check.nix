{
  lib,
  config,
  ...
}: let
  net = import ./_lib.nix {inherit lib;};
  denHosts = lib.concatMapAttrs (_system: hosts: hosts) config.den.hosts;

  # Cross-check each host's mode against its interfaces, caught here rather than as
  # an opaque failure deep in the render or a silently-ignored declaration.
  checkHost = name: host: let
    mode = host.network.mode or "unmanaged";
    ifaces = host.network.interfaces or {};
    hasIfaces = ifaces != {};
  in
    if mode == "static" && !hasIfaces
    then ["network: host '${name}' is mode=static but declares no interfaces"]
    else if mode != "static" && hasIfaces
    then ["network: host '${name}' is mode=${mode} but declares static interfaces (they would be ignored)"]
    else
      lib.flatten (lib.mapAttrsToList (ifName: ifCfg:
        lib.optional (ifCfg.address == "") "network: host '${name}' interface '${ifName}' has an empty address")
      ifaces);

  errors = lib.pipe denHosts [
    (lib.mapAttrsToList checkHost)
    lib.flatten
    (lib.concatStringsSep "\n")
  ];

  # Pure eval tests for the _lib selectors. Run: `fastest --flake .#tests fleet-network`.
  ip = address: {inherit address;};
  hStatic = {
    network = {
      mode = "static";
      interfaces.eno1 = ip "10.0.0.10";
    };
  };
  hMulti = {
    network = {
      mode = "static";
      interfaces = {
        a = ip "10.0.0.1";
        b = ip "10.0.0.2";
      };
    };
  };
  hNM = {
    network = {
      mode = "networkmanager";
      interfaces = {};
    };
  };
  serve = host: lib.recursiveUpdate host {dns.serve.enable = true;};
  t = expr: expected: {inherit expr expected;};
in {
  flake.tests.fleet-network = {
    static-ifaces = t (net.interfacesOf hStatic) ["eno1"];
    static-addrs = t (net.addressesOf hStatic) ["10.0.0.10"];
    nm-ifaces = t (net.interfacesOf hNM) [];
    nm-addrs = t (net.addressesOf hNM) [];
    the-iface = t (net.theInterface hStatic) "eno1";
    the-addr = t (net.theAddress hStatic) "10.0.0.10";
    multi-throws = t (builtins.tryEval (net.theInterface hMulti)).success false;
    nm-the-iface-throws = t (builtins.tryEval (net.theInterface hNM)).success false;
    dns-addrs = t (lib.sort (a: b: a < b) (net.dnsServerAddresses {
      a = serve {
        network = {
          mode = "static";
          interfaces.eno1 = ip "10.0.0.5";
        };
      };
      b = {
        network = {
          mode = "static";
          interfaces.eno1 = ip "10.0.0.6";
        };
      }; # static, not serving
      c = serve hNM; # serving but dynamic -> excluded
    })) ["10.0.0.5"];
  };

  perSystem = {pkgs, ...}: {
    checks.fleet-network-valid = pkgs.runCommand "fleet-network-valid" {inherit errors;} ''
      if [ -n "$errors" ]; then
        echo "invalid host.network config:"
        printf '  %s\n' "$errors"
        exit 1
      fi
      echo ok > $out
    '';
  };
}
