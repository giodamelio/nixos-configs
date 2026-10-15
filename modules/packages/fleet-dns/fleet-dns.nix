{
  inputs,
  config,
  lib,
  ...
}: let
  denHosts = lib.concatMapAttrs (_system: hosts: hosts) config.den.hosts;
  inherit ((builtins.fromTOML (builtins.readFile ../../../homelab.toml))) machines;

  dnsServers = lib.pipe denHosts [
    (lib.filterAttrs (_name: host: host.dns.enable && host.dns.serve.enable))
    (lib.mapAttrsToList (name: _host: {
      inherit name;
      dest =
        machines.${name}.deploy.sshDestination
        or (throw "fleet-dns: DNS server ${name} has no [machines.${name}.deploy] sshDestination in homelab.toml");
    }))
  ];
in {
  # Run from the repo (`nix run .#fleet-dns -- push`): the zones are baked in at
  # build time, so an installed copy would push stale records.
  perSystem = {pkgs, ...}: {
    packages.fleet-dns = inputs.self.lib.writeNushellApplication pkgs {
      name = "fleet-dns";
      runtimeInputs = [pkgs.openssh];
      source = ''
        const zones_dir = "${import ../../aspects/dns/_zones.nix {
          inherit pkgs lib;
          inherit (config.fleet.dns) zones;
        }}"
        const servers = ${builtins.toJSON dnsServers}

        ${builtins.readFile ./fleet-dns.nu}
      '';
      meta = {
        description = "Push the fleet DNS zones to every DNS server without a deploy";
        mainProgram = "fleet-dns";
      };
    };
  };
}
