# A real step-ca built from strontium's own pieces (provisioner flags,
# templates, ca.json settings, CRL endpoint and operator tools), shared by the
# VM tests that enroll gio.mtls certificates.
{
  pkgs,
  lib,
  inputs,
}: let
  # The production path, so ca-enroll-host and ca-revoke run unmodified.
  caDir = "/var/lib/gio-ca";
  pki = pkgs.runCommand "fleet-mtls-test-pki" {nativeBuildInputs = [pkgs.step-cli];} ''
    mkdir $out && cd $out
    export STEPPATH=$TMPDIR/step
    step certificate create "mtls test root" root.crt root.key \
      --profile root-ca --no-password --insecure
    step certificate create "mtls test intermediate" int.crt int.key \
      --profile intermediate-ca --ca root.crt --ca-key root.key --no-password --insecure
  '';
  caJson = pkgs.writeText "ca.json" (builtins.toJSON {
    root = "${caDir}/root.crt";
    crt = "${caDir}/int.crt";
    key = "${caDir}/int.key";
    address = ":443";
    dnsNames = ["ca.gio.ninja"];
    logger.format = "text";
    db = {
      type = "badgerv2";
      dataSource = "${caDir}/db";
    };
    # With 119h certs this makes a fresh cert's validity period 121h but its
    # remaining life 119h: `step ca renew --expires-in 120h` accepts the flag
    # (it must fit the period) and really renews on every run.
    authority = {
      provisioners = [];
      backdate = "2h";
    };
  });
  caConfig = import ../hosts/strontium/_ca-config.nix;
  appFlags = map (f:
    if f == "--x509-default-dur=168h"
    then "--x509-default-dur=119h"
    else f)
  caConfig.provisioners.app;
in {
  inherit caDir pki;
  step = "${pkgs.step-cli}/bin/step";

  tools = certsByHost:
    import ../hosts/strontium/_ca-tools.nix {
      inherit pkgs lib;
      inherit (inputs.self.lib) writeNushellApplication;
    } {mtlsCerts = certsByHost;};

  caModule = {pkgs, ...}: let
    provisioners = import ../hosts/strontium/_provisioners.nix {inherit pkgs lib;} {
      inherit caDir;
      inherit (caConfig) settings;
      group = "root";
      provisioners = caConfig.provisioners // {app = appFlags;};
    };
  in {
    imports = [
      (import ../hosts/strontium/_crl-http.nix {
        caRoot = "${pki}/root.crt";
        caPort = 443;
      })
    ];
    system.stateVersion = "25.11";
    environment.systemPackages = [pkgs.step-cli pkgs.jq provisioners];
    system.activationScripts.testCa = ''
      if [ ! -e ${caDir}/ca.json ]; then
        install -d -m 0750 ${caDir}
        install -m 0644 ${pki}/root.crt ${pki}/int.crt ${caDir}/
        install -m 0600 ${pki}/int.key ${caDir}/
        install -m 0640 ${caJson} ${caDir}/ca.json
      fi
    '';
    systemd.services.step-ca-provisioners = {
      wantedBy = ["multi-user.target"];
      before = ["step-ca.service"];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = lib.getExe provisioners;
      };
    };
    systemd.services.step-ca = {
      wantedBy = ["multi-user.target"];
      after = ["step-ca-provisioners.service"];
      requires = ["step-ca-provisioners.service"];
      serviceConfig.ExecStart = "${pkgs.step-ca}/bin/step-ca ${caDir}/ca.json";
    };
    networking.firewall.allowedTCPPorts = [443];
  };
}
