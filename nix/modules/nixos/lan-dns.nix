{
  pkgs,
  lib,
  ...
}: let
  homelab = builtins.fromTOML (builtins.readFile ../../../homelab.toml);
  a_records = homelab.dns."gio.ninja".a;
  cname_records = homelab.dns."gio.ninja".cname;
  zoneFile = pkgs.writeText "gio.ninja.zone" ''
    $ORIGIN gio.ninja.
    @ IN SOA @ @ 1 1h 15m 30d 2h
      IN NS @

    ${lib.pipe a_records [
      (builtins.mapAttrs (ip: hosts: builtins.map (host: "${host} IN A ${ip}") hosts))
      builtins.attrValues
      builtins.concatLists
      (builtins.concatStringsSep "\n")
    ]}

    ${lib.pipe cname_records [
      (builtins.mapAttrs (ip: hosts: builtins.map (host: "${host} IN CNAME ${ip}") hosts))
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
