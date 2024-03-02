{root, ...}: {pkgs, ...}: let
  ziti = root.packages.ziti {inherit pkgs;};
  networkName = "homelab";
  zitiHome = "/var/lib/ziti";
  defaultServiceConfig = {
    Type = "oneshot";
    DynamicUser = true;
    User = "ziti";
    StateDirectory = "ziti";
  };
  controllerConfig = pkgs.writeTextFile {
    name = "controller.yaml";
    # YAML is a superset of JSON (mostly)
    text = builtins.toJSON {
      v = 3;
      db = "${zitiHome}/db/ctrl.db";
      identity = {
        cert = "${zitiHome}/pki/${networkName}/certs/${networkName}-ctrl-client.cert";
        server_cert = "${zitiHome}/pki/${networkName}/certs/${networkName}-ctrl-server.cert";
        key = "${zitiHome}/pki/${networkName}/keys/${networkName}-ctrl-server.key";
        ca = "${zitiHome}/pki/${networkName}/certs/${networkName}.cert";
      };
      ctrl.listener = "tls:127.0.0.1:6262";
      edge = {
        api = {
          address = "127.0.0.1:1280";
          sessionTimeout = "30m";
        };
        enrollment = {
          signingCert = {
            cert = "${zitiHome}/pki/${networkName}/certs/${networkName}.cert";
            key = "${zitiHome}/pki/${networkName}/keys/${networkName}.key";
          };
          edgeIdentity.durationMinutes = 5;
          edgeRouter.durationMinutes = 5;
        };
      };
      web = [
        {
          name = "all-apis-localhost";
          bindPoints = [
            {
              interface = "127.0.0.1:1280";
              address = "127.0.0.1:1280";
            }
          ];
          apis = [
            {
              binding = "health-checks";
              options = {};
            }
            {
              binding = "fabric";
              options = {};
            }
            {
              binding = "edge-management";
              options = {};
            }
            {
              binding = "edge-client";
              options = {};
            }
          ];
        }
      ];
    };
  };
in {
  # Add the Ziti cli to the system packages
  environment.systemPackages = [ziti];

  # PKI Setup
  # Generates a new PKI if one doesn't exist
  systemd.services.ziti-generate-pki = {
    description = "Generate Ziti PKI";
    wantedBy = ["default.target"];
    serviceConfig = defaultServiceConfig;
    unitConfig = {
      # Only generate if an existing PKI does not exist
      # Note negation of the path
      ConditionPathExists = [
        "!${zitiHome}/pki/${networkName}"
      ];
    };
    script = ''
      # Generate the PKI
      ${ziti}/bin/ziti pki create ca \
        --pki-root="${zitiHome}/pki" \
        --ca-file=${networkName}
    '';
  };

  # Controller Setup
  # Generates the controller identity
  systemd.services.ziti-generate-controller-pki = {
    description = "Generate Ziti controller identity";
    wantedBy = ["default.target"];
    after = ["ziti-generate-pki.service"];
    serviceConfig = defaultServiceConfig;
    unitConfig = {
      # Only generate if an existing PKI does not exist
      # Note negation of the path
      ConditionPathExists = [
        "!${zitiHome}/pki/${networkName}/keys/${networkName}-ctrl-server.key"
      ];
    };
    script = ''
      # Controller config: ${controllerConfig}

      # Generate server key
      ${ziti}/bin/ziti pki create server \
        --pki-root=${zitiHome}/pki \
        --ca-name ${networkName} \
        --server-file "${networkName}-ctrl-server" \
        --dns "${networkName}-ctrl.ziti.gio.ninja" \
        --ip "127.0.0.1" \
        --server-name "${networkName} Controller"

      # Generate client key
      ${ziti}/bin/ziti pki create client \
        --pki-root=${zitiHome}/pki \
        --ca-name ${networkName} \
        --client-file "${networkName}-ctrl-client" \
        --key-file "${networkName}-ctrl-server" \
        --client-name "${networkName} Controller"
    '';
  };

  # Controller Setup
  # Initialize the controller database
  systemd.services.ziti-initialize-controller-database = {
    description = "Initialize Ziti controller database";
    wantedBy = ["default.target"];
    after = ["ziti-generate-controller-pki.service"];
    serviceConfig = defaultServiceConfig;
    unitConfig = {
      # Only generate if an existing PKI does not exist
      # Note negation of the path
      ConditionPathExists = [
        "!${zitiHome}/db/ctrl.db"
      ];
    };
    script = ''
      mkdir -p ${zitiHome}/db
      # TODO: don't hardcode the initial password
      ${ziti}/bin/ziti controller edge init ${controllerConfig} -u admin -p admin
    '';
  };

  # Run the controller
  systemd.services.ziti-controller = {
    description = "Ziti controller";
    wantedBy = ["default.target"];
    after = ["ziti-initialize-controller-database.service"];
    serviceConfig =
      defaultServiceConfig
      // {
        Type = "simple";
      };
    script = ''
      ${ziti}/bin/ziti controller run ${controllerConfig}
    '';
  };
}
