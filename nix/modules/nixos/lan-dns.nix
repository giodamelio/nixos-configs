{
  config,
  pkgs,
  lib,
  ...
}: let
  homelab = builtins.fromTOML (builtins.readFile ../../../homelab.toml);
  homelabNet = config.gio.homelab.networking;
  a_records = homelab.dns."gio.ninja".a;
  aaaa_records = homelab.dns."gio.ninja".aaaa or {};
  cname_records = homelab.dns."gio.ninja".cname;

  # Helper to get a static IP for a CNAME target like "gallium.lan."
  # Returns null if the host doesn't have a static IP
  staticIpForTarget = target: let
    # Strip ".lan." suffix to get the hostname
    hostname = lib.removeSuffix ".lan." target;
    hostNet = homelabNet.${hostname} or null;
  in
    if hostNet != null
    then hostNet.interfaces.${hostNet.primaryInterface}.address
    else null;

  # Like staticIpForTarget, but returns the host's static ULA (sans prefix
  # length) for AAAA generation. null if the host has no ULA configured.
  staticUlaForTarget = target: let
    hostname = lib.removeSuffix ".lan." target;
    hostNet = homelabNet.${hostname} or null;
    ula =
      if hostNet != null
      then hostNet.interfaces.${hostNet.primaryInterface}.ula
      else null;
  in
    if ula != null
    then lib.head (lib.splitString "/" ula)
    else null;

  # Split CNAME records into those that can become A records and those that stay as CNAMEs
  staticTargets = lib.filterAttrs (target: _: staticIpForTarget target != null) cname_records;
  dynamicTargets = lib.filterAttrs (target: _: staticIpForTarget target == null) cname_records;

  # Convert static targets into A records: ip -> [hosts]
  staticARecords = lib.pipe staticTargets [
    (lib.mapAttrsToList (target: hosts: {
      ip = staticIpForTarget target;
      inherit hosts;
    }))
    (builtins.groupBy (entry: entry.ip))
    (builtins.mapAttrs (_ip: entries: lib.concatMap (e: e.hosts) entries))
  ];

  # Merge explicit A records from TOML with generated ones from static IPs
  allARecords = lib.recursiveUpdate a_records staticARecords;

  # AAAA records generated from host ULAs. Only CNAME targets that already
  # resolve to a static A record qualify, so a name is never both AAAA and
  # CNAME (which DNS forbids).
  ulaTargets = lib.filterAttrs (target: _:
    staticIpForTarget target != null && staticUlaForTarget target != null)
  cname_records;

  staticAAAARecords = lib.pipe ulaTargets [
    (lib.mapAttrsToList (target: hosts: {
      ip = staticUlaForTarget target;
      inherit hosts;
    }))
    (builtins.groupBy (entry: entry.ip))
    (builtins.mapAttrs (_ip: entries: lib.concatMap (e: e.hosts) entries))
  ];

  allAAAARecords = lib.recursiveUpdate aaaa_records staticAAAARecords;

  zoneFile = pkgs.writeText "gio.ninja.zone" ''
    $ORIGIN gio.ninja.
    @ IN SOA @ @ 1 1h 15m 30d 2h
      IN NS @

    ${lib.pipe allARecords [
      (builtins.mapAttrs (ip: hosts: map (host: "${host} IN A ${ip}") hosts))
      builtins.attrValues
      builtins.concatLists
      (builtins.concatStringsSep "\n")
    ]}

    ${lib.pipe allAAAARecords [
      (builtins.mapAttrs (ip: hosts: map (host: "${host} IN AAAA ${ip}") hosts))
      builtins.attrValues
      builtins.concatLists
      (builtins.concatStringsSep "\n")
    ]}

    ${lib.pipe dynamicTargets [
      (builtins.mapAttrs (target: hosts: map (host: "${host} IN CNAME ${target}") hosts))
      builtins.attrValues
      builtins.concatLists
      (builtins.concatStringsSep "\n")
    ]}
  '';
in {
  services.resolved = {
    settings = {
      Resolve = {
        DNSStubListener = "no";
      };
    };
  };

  services.coredns = {
    enable = true;
    config = ''
      gio.ninja:53 {
          file ${zoneFile} {
            fallthrough
          }
          forward . 1.1.1.1 1.0.0.1
          errors
          cache
      }

      lan:53 {
        forward . 10.0.0.1
        errors
        cache
      }

      consul:53 {
        forward . 127.0.0.1:8600
        errors
        cache
      }

      .:53 {
          forward . 1.1.1.1 1.0.0.1
          errors
          cache
      }
    '';
  };

  # Open the firewall
  networking.firewall = {
    allowedTCPPorts = [
      53
    ];
    allowedUDPPorts = [
      53
    ];
  };
}
