# NFS certificate lifecycle against a real step-ca: the CA VM's `nfs`
# provisioner is created by the same script strontium runs
# (hosts/strontium/_provisioners.nix); a token minted there and dropped into the
# client's enroll-token file is consumed by the nfs-cert-enroll path unit; the
# daily renewer then rotates the certificate and restarts tlshd.
_: {
  perSystem = {
    pkgs,
    lib,
    ...
  }: let
    caDir = "/var/lib/ca";
    pki = pkgs.runCommand "fleet-nfs-cert-test-pki" {nativeBuildInputs = [pkgs.step-cli];} ''
      mkdir $out && cd $out
      export STEPPATH=$TMPDIR/step
      step certificate create "nfs-cert test root" root.crt root.key \
        --profile root-ca --no-password --insecure
      step certificate create "nfs-cert test intermediate" int.crt int.key \
        --profile intermediate-ca --ca root.crt --ca-key root.key --no-password --insecure
    '';
    caJson = pkgs.writeText "ca.json" (builtins.toJSON {
      root = "${caDir}/root.crt";
      crt = "${caDir}/int.crt";
      key = "${caDir}/int.key";
      address = ":443";
      dnsNames = ["ca.gio.ninja"];
      db = {
        type = "badgerv2";
        dataSource = "${caDir}/db";
      };
      authority.provisioners = [];
    });
    managed = {nfs = ["--ssh=false" "--x509-default-dur=168h" "--x509-max-dur=168h"];};
  in {
    denTests.fleet-nfs-cert = {
      fleet = _: {
        den.hosts.x86_64-linux = {
          ca.ssh.hostKey = null;
          nfs-cl = {
            ssh.hostKey = null;
            nfs.enable = true;
          };
        };
        fleet.nfs.caRoot = "${pki}/root.crt";

        den.aspects.ca.nixos = {pkgs, ...}: let
          provisioners = import ../hosts/strontium/_provisioners.nix {inherit pkgs lib;} {
            inherit caDir;
            group = "root";
            provisioners = managed;
          };
        in {
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
        den.aspects.nfs-cl.nixos = _: {system.stateVersion = "25.11";};
      };

      nodes = {
        ca = "ca";
        client = "nfs-cl";
      };

      node = _: {
        nodes,
        lib,
        ...
      }: {
        networking.extraHosts = lib.mkAfter ''
          ${nodes.ca.networking.primaryIPAddress} ca.gio.ninja
        '';
      };

      testScript = ''
        import json

        start_all()
        ca.wait_for_unit("step-ca.service")
        ca.wait_for_open_port(443)
        client.wait_for_unit("multi-user.target")

        with subtest("the provisioner script creates nfs offline and is idempotent"):
            prov = json.loads(ca.succeed(
                "jq -c '.authority.provisioners[] | select(.name == \"nfs\")' ${caDir}/ca.json"
            ))
            assert prov["type"] == "JWK" and prov["encryptedKey"], prov
            assert prov["claims"]["enableSSHCA"] is False, prov["claims"]
            assert prov["claims"]["maxTLSCertDuration"].startswith("168h"), prov["claims"]
            ca.succeed("cp ${caDir}/ca.json /tmp/before.json")
            ca.succeed("step-ca-provisioners")
            ca.succeed("cmp /tmp/before.json ${caDir}/ca.json")

        with subtest("an unenrolled client keeps tlshd and the renewer dormant"):
            client.fail("systemctl is-active tlshd.service")
            client.succeed("systemctl start nfs-cert-renew.service")
            client.fail("test -e /var/lib/step-nfs/cert.pem")

        def mint():
            return ca.succeed(
                "step ca token nfs-cl.gio.ninja --san nfs-cl.gio.ninja --san nfs-cl "
                "--provisioner nfs --provisioner-password-file ${caDir}/provisioners/nfs/password "
                "--not-after 30m --ca-url https://ca.gio.ninja --root ${caDir}/root.crt"
            ).strip()

        def drop(token):
            # Exactly the command ca-enroll-host prints.
            client.succeed(
                f"bash -c \"install -D -m 0600 /dev/stdin /var/lib/step-nfs/enroll-token <<< '{token}'\""
            )

        def inspect():
            return json.loads(client.succeed(
                "step certificate inspect --format json /var/lib/step-nfs/cert.pem"
            ))

        token = mint()
        with subtest("dropping a token enrolls the host and starts tlshd"):
            drop(token)
            client.wait_for_file("/var/lib/step-nfs/cert.pem")
            client.wait_until_fails("test -e /var/lib/step-nfs/enroll-token")
            client.wait_for_unit("tlshd.service")
            cert = inspect()
            assert "nfs-cl.gio.ninja" in cert["names"], cert["names"]
            client.succeed(
                "step certificate verify /var/lib/step-nfs/cert.pem --roots ${pki}/root.crt "
                "--host nfs-cl.gio.ninja"
            )
            lifetime = client.succeed(
                "step certificate inspect --format json /var/lib/step-nfs/cert.pem "
                "| ${pkgs.jq}/bin/jq -r '((.validity.end | fromdate) - (.validity.start | fromdate))'"
            ).strip()
            # 168h, allowing for step-ca's backdate of the start.
            assert 167 * 3600 <= float(lifetime) <= 169 * 3600, lifetime

        with subtest("a used token is refused and removed"):
            serial = inspect()["serial_number"]
            drop(token)
            client.wait_until_fails("test -e /var/lib/step-nfs/enroll-token")
            client.wait_until_succeeds("systemctl is-failed nfs-cert-enroll.service")
            assert inspect()["serial_number"] == serial, "cert changed on a reused token"

        with subtest("renewal rotates the certificate and restarts tlshd"):
            before = client.succeed("systemctl show -p InvocationID --value tlshd.service").strip()
            client.succeed("systemctl start nfs-cert-renew.service")
            assert inspect()["serial_number"] != serial, "renewal kept the old serial"
            after = client.succeed("systemctl show -p InvocationID --value tlshd.service").strip()
            assert before != after, "tlshd was not restarted"
            client.succeed("systemctl is-active tlshd.service")
      '';
    };
  };
}
