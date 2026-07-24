# step-ca — homelab SSH certificate authority (Phase 1: SSH-first, JWK).
# Signing keys were placed by the ceremony (docs/archive/ca-ceremony-runbook.md);
# ca.json + the JWK bootstrap provisioner are generated on-box into
# /var/lib/gio-ca, never the Nix store (docs/pi-ca-secrets-plan.md).
{inputs, ...}: {
  den.aspects.strontium.nixos = {
    pkgs,
    lib,
    ...
  }: let
    caDir = "/var/lib/gio-ca";
    caJson = "${caDir}/ca.json";
    caPort = 443;

    # Enroll a host: mint a one-time token here (CA side, holds the provisioner
    # password) and print the ready-to-paste command for the target host.
    enrollTool = inputs.self.lib.writeNushellApplication pkgs {
      name = "ca-enroll-host";
      runtimeInputs = [pkgs.systemd pkgs.step-cli];
      source = builtins.readFile ./ca-enroll.nu;
      meta.mainProgram = "ca-enroll-host";
    };

    # Idempotent: builds ca.json + a fresh JWK provisioner only when ca.json is
    # absent (regenerate by removing it). The provisioner private JWK is stored
    # encrypted under the provisioner password, which arrives as a systemd
    # credential and never lands in the config file plaintext.
    initScript = pkgs.writeShellApplication {
      name = "step-ca-init";
      runtimeInputs = [pkgs.step-cli pkgs.jq pkgs.coreutils];
      text = ''
        if [ -e ${caJson} ]; then
          echo "ca.json already present; nothing to do"
          exit 0
        fi

        pw="$CREDENTIALS_DIRECTORY/step_ca_provisioner_password"
        work="$(mktemp -d)"
        trap 'rm -rf "$work"' EXIT

        step crypto jwk create "$work/jwk.pub.json" "$work/jwk.key.json" \
          --use sig --password-file "$pw"

        # step-ca wants the private JWK as a compact JWE; step emits it flattened.
        enc="$(jq -r '[.protected,.encrypted_key,.iv,.ciphertext,.tag]|join(".")' "$work/jwk.key.json")"

        jq -n \
          --slurpfile pub "$work/jwk.pub.json" \
          --arg enc "$enc" \
          --arg dir "${caDir}" \
          --arg addr ":${toString caPort}" \
          '{
            root: ($dir + "/root.crt"),
            crt: ($dir + "/intermediate.crt"),
            key: ($dir + "/intermediate.key"),
            address: $addr,
            dnsNames: ["ca.gio.ninja", "strontium", "10.30.0.13"],
            ssh: {
              hostKey: ($dir + "/ssh_host_ca"),
              userKey: ($dir + "/ssh_user_ca")
            },
            logger: {format: "text"},
            db: {type: "badgerv2", dataSource: "/var/lib/step-ca/db"},
            authority: {
              provisioners: [
                {
                  type: "JWK",
                  name: "bootstrap",
                  key: $pub[0],
                  encryptedKey: $enc,
                  claims: {
                    enableSSHCA: true,
                    defaultHostSSHCertDuration: "720h",
                    maxHostSSHCertDuration: "720h"
                  }
                },
                {
                  type: "SSHPOP",
                  name: "sshpop",
                  claims: {
                    enableSSHCA: true,
                    defaultHostSSHCertDuration: "720h",
                    maxHostSSHCertDuration: "720h"
                  }
                }
              ]
            }
          }' > "$work/ca.json"

        install -m0640 -o root -g step-ca "$work/ca.json" ${caJson}
      '';
    };
  in {
    # agevault delivers the provisioner password (asserted against secrets.toml).
    fleet.credentials.needs = ["step_ca_provisioner_password"];

    users.groups.step-ca = {};
    users.users.step-ca = {
      isSystemUser = true;
      group = "step-ca";
      home = "/var/lib/step-ca";
    };

    # Grant the step-ca user read access to the ceremony-placed key material.
    # `z` only adjusts existing paths, so this never creates/overwrites keys —
    # it just relaxes group perms idempotently on each activation.
    systemd.tmpfiles.rules = [
      "z ${caDir}                  0750 root step-ca - -"
      "z ${caDir}/intermediate.key 0640 root step-ca - -"
      "z ${caDir}/intermediate.crt 0644 root step-ca - -"
      "z ${caDir}/root.crt         0644 root step-ca - -"
      "z ${caDir}/ssh_user_ca      0640 root step-ca - -"
      "z ${caDir}/ssh_host_ca      0640 root step-ca - -"
    ];

    systemd.services.step-ca-init = {
      description = "Generate step-ca config + JWK provisioner (once)";
      wantedBy = ["multi-user.target"];
      before = ["step-ca.service"];
      unitConfig.ConditionPathExists = "!${caJson}";
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        LoadCredentialEncrypted = ["step_ca_provisioner_password"];
        ExecStart = lib.getExe initScript;
      };
    };

    systemd.services.step-ca = {
      description = "Homelab step-ca certificate authority";
      wantedBy = ["multi-user.target"];
      wants = ["network-online.target"];
      after = ["network-online.target" "step-ca-init.service"];
      requires = ["step-ca-init.service"];
      # Intermediate key is unencrypted (ceremony used --no-password), so no
      # --password-file; step-ca loads it directly.
      serviceConfig = {
        Type = "simple";
        User = "step-ca";
        Group = "step-ca";
        StateDirectory = "step-ca";
        WorkingDirectory = "/var/lib/step-ca";
        Environment = "HOME=/var/lib/step-ca";
        ExecStart = "${pkgs.step-ca}/bin/step-ca ${caJson}";
        Restart = "on-failure";
        RestartSec = 5;

        AmbientCapabilities = ["CAP_NET_BIND_SERVICE"];
        CapabilityBoundingSet = ["CAP_NET_BIND_SERVICE"];
        NoNewPrivileges = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;
        ReadOnlyPaths = [caDir];
        RestrictAddressFamilies = ["AF_INET" "AF_INET6" "AF_UNIX"];
      };
    };

    networking.firewall.allowedTCPPorts = [caPort];

    environment.systemPackages = [pkgs.step-cli enrollTool];
  };
}
