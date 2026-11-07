# The CA-side operator tools, shared by strontium and the mtls VM test.
# `mtlsCerts` is host -> that host's evaluated gio.mtls.certs.
{
  pkgs,
  lib,
  writeNushellApplication,
}: {mtlsCerts}: let
  identities = lib.mapAttrs (_host:
    lib.mapAttrs (_name: c: {
      inherit (c) cn role uri;
      dns = c.serverHostnames;
      ips = c.serverAddresses;
    }))
  mtlsCerts;
in {
  # Enroll a host: mint one-time tokens here (CA side, holds the provisioner
  # passwords) and print the ready-to-paste commands for the target host.
  enroll = writeNushellApplication pkgs {
    name = "ca-enroll-host";
    runtimeInputs = [pkgs.systemd pkgs.step-cli];
    source = ''
      const mtls_certs = ${builtins.toJSON identities}
      ${builtins.readFile ./ca-enroll.nu}
    '';
    meta.mainProgram = "ca-enroll-host";
  };

  revoke = writeNushellApplication pkgs {
    name = "ca-revoke";
    runtimeInputs = [pkgs.systemd pkgs.step-cli];
    source = builtins.readFile ./ca-revoke.nu;
    meta.mainProgram = "ca-revoke";
  };
}
