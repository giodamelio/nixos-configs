{inputs, ...}: let
  root = "/var/lib/mtls";
  tokensDir = "${root}/tokens";
in {
  den.aspects.mtls.nixos = {
    config,
    fleet,
    host,
    lib,
    pkgs,
    ...
  }: let
    inherit (lib) mkOption types;
    cfg = config.gio.mtls;

    unitOf = s: "${lib.removeSuffix ".service" s}.service";
    groupOf = c:
      if c.onRenew == "reload-caddy"
      then "caddy"
      else "root";

    certType = types.submodule ({
      name,
      config,
      ...
    }: {
      options = {
        app = mkOption {
          type = types.str;
          default = name;
          description = "Application name; the CN is `<app>.<host>`.";
        };
        role = mkOption {
          type = types.str;
          description = "Role, signed into the certificate as its OU. Callers are authorized by it.";
        };
        serverHostnames = mkOption {
          type = types.listOf types.str;
          default = [];
          description = "DNS SANs, only for names that resolve to this host. Pure clients have none.";
        };
        serverAddresses = mkOption {
          type = types.listOf types.str;
          default = [];
          description = ''
            IP SANs, only for addresses that belong to this host, for peers that
            dial and verify by IP. Write them in canonical form (`fd00::1`), as
            the drift check compares them verbatim.
          '';
        };
        services = mkOption {
          type = types.listOf types.str;
          default = [];
          description = ''
            systemd services (".service" optional) that consume the certificate.
            Each gets LoadCredential= mtls-<name>-cert, mtls-<name>-key and mtls-ca.
          '';
        };
        onRenew = mkOption {
          type = types.enum ["restart" "reload" "reload-caddy"];
          description = ''
            What a new certificate triggers: restart or reload `services`, or
            reload caddy.service (which then reads certFile/keyFile directly).
          '';
        };
        cn = mkOption {
          type = types.str;
          readOnly = true;
          default = "${config.app}.${host.name}";
          description = "Common name, derived from app and host.";
        };
        uri = mkOption {
          type = types.str;
          readOnly = true;
          default = "spiffe://gio.ninja/${host.name}/${config.app}";
          description = "URI SAN, derived from app and host.";
        };
        certFile = mkOption {
          type = types.str;
          readOnly = true;
          default = "${root}/${name}/cert.pem";
          description = "Certificate path (root-owned).";
        };
        keyFile = mkOption {
          type = types.str;
          readOnly = true;
          default = "${root}/${name}/key.pem";
          description = "Private key path (root-owned).";
        };
      };
    });

    certs =
      lib.mapAttrs (_name: c: {
        inherit (c) cn role uri certFile keyFile onRenew;
        dns = lib.sort lib.lessThan (lib.unique c.serverHostnames);
        ips = lib.sort lib.lessThan (lib.unique c.serverAddresses);
        units = map unitOf c.services;
        group = groupOf c;
      })
      cfg.certs;

    tool = inputs.self.lib.writeNushellApplication pkgs {
      name = "mtls";
      runtimeInputs = [pkgs.step-cli pkgs.systemd pkgs.coreutils];
      source = ''
        const certs = ${builtins.toJSON certs}
        const host = "${host.name}"
        const ca_root = "${cfg.caRoot}"
        ${builtins.readFile ./mtls.nu}
      '';
      meta.mainProgram = "mtls";
    };

    certNamesByUnit = lib.foldlAttrs (acc: name: c:
      lib.foldl' (a: unit: a // {${unit} = (a.${unit} or []) ++ [name];}) acc c.units) {}
    certs;

    duplicateCns = lib.pipe certs [
      lib.attrValues
      (lib.groupBy (c: c.cn))
      (lib.filterAttrs (_: cs: builtins.length cs > 1))
      lib.attrNames
    ];
  in {
    options.gio.mtls = {
      certs = mkOption {
        type = types.attrsOf certType;
        default = {};
        description = ''
          Certificates from strontium's step-ca `app` provisioner, enrolled once
          with `ca-enroll-host <host> mtls` and renewed by mtls-renew.timer.
          See modules/aspects/mtls/README.md.
        '';
      };
      caRoot = mkOption {
        type = types.str;
        readOnly = true;
        default = "/etc/step/ca-root.crt";
        description = "step-ca root certificate, for trust pools.";
      };
    };

    config = lib.mkIf (cfg.certs != {}) {
      assertions = [
        {
          assertion = duplicateCns == [];
          message = "gio.mtls: several certs on ${host.name} share a CN (give them distinct `app`s): ${toString duplicateCns}";
        }
        {
          assertion = lib.all (c: c.group != "caddy" || config.users.groups ? caddy) (lib.attrValues certs);
          message = "gio.mtls: onRenew = \"reload-caddy\" on ${host.name}, which has no caddy group (is services.caddy enabled?)";
        }
      ];

      # Public material; a host whose SSH renewer already installs it keeps that.
      environment.etc."step/ca-root.crt".source = lib.mkDefault fleet.nfs.caRoot;

      systemd.tmpfiles.rules =
        [
          "d ${root} 0711 root root - -"
          "d ${tokensDir} 0700 root root - -"
        ]
        ++ lib.concatLists (lib.mapAttrsToList (name: c: let
            mode =
              if c.group == "root"
              then "0700"
              else "0750";
          in [
            "d ${root}/${name} ${mode} root ${c.group} - -"
            # `z` only adjusts files that exist, so an onRenew change is applied
            # to an already enrolled cert.
            "z ${c.certFile} 0640 root ${c.group} - -"
            "z ${c.keyFile} 0640 root ${c.group} - -"
          ])
          certs);

      systemd.services =
        lib.mapAttrs' (unit: names:
          lib.nameValuePair (lib.removeSuffix ".service" unit) {
            # LoadCredential= fails a unit whose file is missing, so before
            # enrollment it stays dormant instead; mtls-enroll starts it.
            unitConfig.ConditionPathExists = map (name: certs.${name}.certFile) names;
            serviceConfig.LoadCredential = lib.unique (lib.concatMap (name: [
                "mtls-${name}-cert:${certs.${name}.certFile}"
                "mtls-${name}-key:${certs.${name}.keyFile}"
                "mtls-ca:${cfg.caRoot}"
              ])
              names);
          })
        certNamesByUnit
        // {
          mtls-enroll = {
            description = "Enroll gio.mtls certificates from dropped tokens";
            after = ["network-online.target"];
            wants = ["network-online.target"];
            serviceConfig = {
              Type = "oneshot";
              ExecStart = "${lib.getExe tool} enroll";
            };
          };

          mtls-renew = {
            description = "Check and renew gio.mtls certificates";
            after = ["network-online.target"];
            wants = ["network-online.target"];
            # Dormant (not failed) until a certificate is enrolled.
            unitConfig.ConditionPathExistsGlob = "${root}/*/cert.pem";
            serviceConfig = {
              Type = "oneshot";
              ExecStart = "${lib.getExe tool} renew";
            };
          };
        };

      systemd.paths.mtls-enroll = {
        description = "Enroll gio.mtls certificates once a token is dropped";
        wantedBy = ["multi-user.target"];
        pathConfig.PathExistsGlob = "${tokensDir}/*.token";
      };

      systemd.timers.mtls-renew = {
        description = "Twice-daily gio.mtls certificate renewal";
        wantedBy = ["timers.target"];
        timerConfig = {
          OnCalendar = "00/12:00";
          Persistent = true;
          RandomizedDelaySec = "1h";
        };
      };
    };
  };
}
