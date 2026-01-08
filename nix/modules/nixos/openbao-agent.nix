# Adapted from https://github.com/NixOS/nixpkgs/blob/nixos-25.11/nixos/modules/services/security/vault-agent.nix
{
  pkgs,
  lib,
  config,
  ...
}: let
  format = pkgs.formats.json {};
  createAgentInstance = {
    instance,
    name,
  }: let
    configFile = format.generate "${name}.json" instance.settings;
  in
    lib.mkIf instance.enable {
      description = "OpenBao daemon - ${name}";
      wantedBy = ["multi-user.target"];
      after = ["network.target"];
      path = [pkgs.getent];
      startLimitIntervalSec = 60;
      startLimitBurst = 3;
      serviceConfig = {
        User = instance.user;
        Group = instance.group;
        RuntimeDirectory = "openbao-agent";
        ExecStart = "${lib.getExe pkgs.openbao} agent -config ${configFile}";
        ExecReload = "${pkgs.coreutils}/bin/kill -SIGHUP $MAINPID";
        KillSignal = "SIGINT";
        TimeoutStopSec = "30s";
        Restart = "on-failure";
      };
    };
in {
  options = {
    services.gio.openbao-agent.instances = lib.mkOption {
      default = {};
      description = ''
        Attribute set of OpenBao agent instances.
        Creates independent `openbao-agent-''${name}.service` systemd units for each instance defined here.
      '';
      type = with lib.types;
        attrsOf (
          submodule (
            {name, ...}: {
              options = {
                enable =
                  lib.mkEnableOption "this openbao agent instance"
                  // {
                    default = true;
                  };

                user = lib.mkOption {
                  type = types.str;
                  default = "root";
                  description = ''
                    User under which this instance runs.
                  '';
                };

                group = lib.mkOption {
                  type = types.str;
                  default = "root";
                  description = ''
                    Group under which this instance runs.
                  '';
                };

                settings = lib.mkOption {
                  type = types.submodule {
                    freeformType = format.type;

                    options = {
                      pid_file = lib.mkOption {
                        default = "/run/openbao-agent/${name}.pid";
                        type = types.str;
                        description = ''
                          Path to use for the pid file.
                        '';
                      };
                    };
                  };

                  default = {};

                  description = ''
                    Free-form settings written directly to the `config.json` file.
                    Refer to <https://openbao.org/docs/agent-and-proxy/agent/#configuration> for supported values.

                    ::: {.note}
                    Resulting format is JSON not HCL.
                    Refer to <https://www.hcl2json.com/> if you are unsure how to convert HCL options to JSON.
                    :::
                  '';
                };
              };
            }
          )
        );
    };
  };

  config = let
    cfg = config.services.gio.openbao-agent;
  in
    lib.mkIf (cfg.instances != {}) {
      systemd.services =
        lib.mapAttrs' (
          name: instance:
            lib.nameValuePair "openbao-agent-${name}" (createAgentInstance {
              inherit name instance;
            })
        )
        cfg.instances;
    };
}
