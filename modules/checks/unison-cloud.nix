_: let
  consulManagementToken = "3bedfa82-175d-4b42-8e90-67fdbd3f1645";
  gossipKey = "BLA6sMz8r34hBj+te15YGWHbyTpM43Ey3yorD9rtQ10=";

  secrets = {
    unison_cloud_oidc_client_secret = "test-oidc-client-secret";
    unison_cloud_s3_access_key_id = "GK31c2f218a2e44f485b94239e";
    unison_cloud_s3_secret_access_key = "b892c0665f0ada8a4755dae98baa3b133590e11dae3bcc1f9d769d67f16c3835";
    unison_cloud_api_db_password = "test-cloud-api-db-password";
    unison_cloud_nimbus_db_password = "test-nimbus-db-password";
    unison_cloud_consul_token = "0d9c8b7a-6f5e-4d3c-9b2a-1f0e9d8c7b6a";
  };

  s3Host = "s3.garage.gio.ninja";
in {
  perSystem.denTests.unison-cloud = {
    fleet = {den, ...}: {
      den.hosts.x86_64-linux.srv = {
        ssh.hostKey = null;
        consul.enable = true;
        network.interfaces.eth0.address = "10.99.0.1";
      };

      den.aspects.srv = {
        includes = [den.aspects.unison-cloud den.aspects.postgresql];
        nixos = {
          config,
          lib,
          pkgs,
          ...
        }: let
          cfg = config.services.unison-cloud;
          consumers = [
            "unison-cloud-secrets.service"
            "unison-cloud-postgresql-setup.service"
          ];
        in {
          system.stateVersion = "25.11";
          nixpkgs.config.allowUnfree = true;
          environment.systemPackages = [pkgs.consul];
          networking.nftables.enable = true;
          virtualisation = {
            memorySize = 6144;
            cores = 4;
          };

          fleet.credentials.manifestFile = builtins.toFile "manifest.toml" ''
            srv = ["consul_encrypt", "consul_acl_tokens", ${lib.concatMapStringsSep ", " (n: ''"${n}"'') (lib.attrNames secrets)}]
          '';

          services.unison-cloud = {
            nimbus.nodes.interactive = 1;
            s3 = {
              port = 3900;
              https = false;
            };
          };

          # No Cloudflare token in a VM.
          services.gio.reverse-proxy.virtualHosts = lib.genAttrs ["unison-cloud-api" "unison-cloud-apps" "unison-cloud-ui"] (_: {
            tls = false;
            listenPort = 80;
          });

          networking.hosts."127.0.0.1" = [s3Host "${cfg.s3.buckets.services}.${s3Host}" "${cfg.s3.buckets.userBlobs}.${s3Host}"];

          # Encrypted under their credstore names, as agevault does, so the name check is real.
          systemd.services.unison-cloud-test-credentials = {
            requiredBy = consumers;
            before = consumers;
            path = [config.systemd.package];
            serviceConfig = {
              Type = "oneshot";
              RemainAfterExit = true;
            };
            script = ''
              install -d -m 0700 /etc/credstore.encrypted
              ${lib.concatStrings (lib.mapAttrsToList (name: value: ''
                  printf '%s' ${lib.escapeShellArg value} | systemd-creds encrypt --name=${name} - /etc/credstore.encrypted/${name}
                '')
                secrets)}
            '';
          };

          environment.etc."test-consul-encrypt".text = builtins.toJSON {encrypt = gossipKey;};
          environment.etc."test-consul-acl-tokens".text = builtins.toJSON {
            acl.tokens = {
              initial_management = consulManagementToken;
              agent = consulManagementToken;
              config_file_service_registration = consulManagementToken;
            };
          };
          systemd.services.consul.serviceConfig = {
            LoadCredentialEncrypted = lib.mkForce [];
            LoadCredential = [
              "consul_encrypt:/etc/test-consul-encrypt"
              "consul_acl_tokens:/etc/test-consul-acl-tokens"
            ];
          };

          systemd.services.unison-cloud-test-consul-token = {
            requires = ["consul.service"];
            after = ["consul.service"];
            requiredBy = ["unison-cloud-consul-services.service" "unison-cloud-api.service"];
            before = ["unison-cloud-consul-services.service" "unison-cloud-api.service"];
            path = [config.services.consul.package];
            environment.CONSUL_HTTP_TOKEN = consulManagementToken;
            serviceConfig = {
              Type = "oneshot";
              RemainAfterExit = true;
            };
            script = ''
              until consul acl policy list >/dev/null; do sleep 1; done
              consul acl policy create -name unison-cloud -rules @${cfg.consul.aclPolicy}
              consul acl token create -policy-name unison-cloud -secret ${secrets.unison_cloud_consul_token}
            '';
          };

          services.garage = {
            enable = true;
            package = pkgs.garage_2;
            settings = {
              replication_factor = 1;
              rpc_bind_addr = "127.0.0.1:3901";
              rpc_public_addr = "127.0.0.1:3901";
              rpc_secret = "fedcba9876543210fedcba9876543210fedcba9876543210fedcba9876543210";
              s3_api = {
                api_bind_addr = "127.0.0.1:3900";
                s3_region = "garage";
                root_domain = ".${s3Host}";
              };
            };
          };

          systemd.services.garage-setup = {
            requires = ["garage.service"];
            after = ["garage.service"];
            requiredBy = ["unison-cloud-api.service"];
            before = ["unison-cloud-api.service"];
            path = [config.services.garage.package pkgs.coreutils];
            serviceConfig = {
              Type = "oneshot";
              RemainAfterExit = true;
            };
            script = ''
              until garage status; do sleep 1; done
              node=$(garage node id -q | cut -d@ -f1)
              garage layout assign -z dc1 -c 1G "$node"
              garage layout apply --version 1
              garage key import --yes -n unison-cloud ${secrets.unison_cloud_s3_access_key_id} ${secrets.unison_cloud_s3_secret_access_key}
              for bucket in ${cfg.s3.buckets.services} ${cfg.s3.buckets.userBlobs}; do
                garage bucket create "$bucket"
                garage bucket allow --read --write --owner "$bucket" --key unison-cloud
              done
            '';
          };

          services.loki = {
            enable = true;
            configuration = {
              auth_enabled = false;
              server.http_listen_port = 3100;
              common = {
                path_prefix = "/var/lib/loki";
                instance_addr = "127.0.0.1";
                storage.filesystem = {
                  chunks_directory = "/var/lib/loki/chunks";
                  rules_directory = "/var/lib/loki/rules";
                };
                replication_factor = 1;
                ring.kvstore.store = "inmemory";
              };
              schema_config.configs = [
                {
                  from = "2025-10-27";
                  store = "tsdb";
                  object_store = "filesystem";
                  schema = "v13";
                  index = {
                    prefix = "index_";
                    period = "24h";
                  };
                }
              ];
            };
          };
        };
      };
    };

    nodes.srv = "srv";
    node = _: {pkgs, ...}: {environment.systemPackages = [pkgs.curl pkgs.jq pkgs.postgresql];};

    testScript = ''
      srv.start()

      with subtest("every Unison Cloud unit comes up"):
          for unit in [
              "unison-cloud-postgresql-setup",
              "unison-cloud-api",
              "unison-cloud-nimbus-public-daemon-0",
              "unison-cloud-nimbus-interactive-0",
              "unison-cloud-consul-services",
              "unison-cloud-log-shipper",
          ]:
              srv.wait_for_unit(f"{unit}.service", timeout=600)

      with subtest("Caddy serves the API's discovery document"):
          srv.wait_until_succeeds(
              "curl -sf --resolve api.unison.gio.ninja:80:127.0.0.1"
              + " http://api.unison.gio.ninja/.well-known/openid-configuration"
              + " | jq -e '.issuer | startswith(\"https://api.unison.gio.ninja\")'"
          )

      with subtest("Caddy hides cloud-api's internal routes"):
          srv.succeed(
              "curl -s -o /dev/null -w '%{http_code}' --resolve api.unison.gio.ninja:80:127.0.0.1"
              + " http://api.unison.gio.ninja/internal/health | grep -qx 404"
          )

      with subtest("Caddy serves the UI"):
          srv.succeed("curl -sf --resolve unison.gio.ninja:80:127.0.0.1 http://unison.gio.ninja/ | grep -qi '<html'")

      with subtest("each role reaches only its own database"):
          srv.succeed("PGPASSWORD=${secrets.unison_cloud_api_db_password} psql -h 127.0.0.1 -U unison_cloud -d unison_cloud -c 'SELECT 1'")
          srv.fail("PGPASSWORD=${secrets.unison_cloud_api_db_password} psql -h 127.0.0.1 -U unison_cloud -d unison_cloud_nimbus -c 'SELECT 1'")
          srv.fail("PGPASSWORD=${secrets.unison_cloud_nimbus_db_password} psql -h 127.0.0.1 -U unison_cloud_nimbus -d unison_cloud -c 'SELECT 1'")

      with subtest("the nimbus client ports are registered under the policy's prefix"):
          srv.wait_until_succeeds(
              "CONSUL_HTTP_TOKEN=${consulManagementToken} consul catalog services | grep -qx unison-cloud-nimbus-client"
          )
    '';
  };
}
