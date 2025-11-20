{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.gio.credentials;

  # Generate a wrapper script for a service
  mkExecStartWrapper = serviceName: serviceCfg: let
    wrapperCfg = serviceCfg.execStartWrapper;

    # Build the sourcing commands for env files
    envFileSources =
      concatMapStringsSep "\n" (credName: ''
        if [ -f "''${CREDENTIALS_DIRECTORY}/${credName}" ]; then
          set -a
          . "''${CREDENTIALS_DIRECTORY}/${credName}"
          set +a
        fi
      '')
      wrapperCfg.envfiles;

    # Build the export commands for individual credentials
    envExports = concatStringsSep "\n" (mapAttrsToList (envVar: credName: ''
        if [ -f "''${CREDENTIALS_DIRECTORY}/${credName}" ]; then
          export ${envVar}="$(cat "''${CREDENTIALS_DIRECTORY}/${credName}")"
        fi
      '')
      wrapperCfg.environment);

    # Get the original ExecStart from the service config
    originalService = config.systemd.services.${serviceName};
    originalExecStart = originalService.serviceConfig.ExecStart or null;
  in
    pkgs.writeShellScript "${serviceName}-credential-wrapper" ''
      set -e

      # Source environment files
      ${envFileSources}

      # Export individual credentials as environment variables
      ${envExports}

      # Execute the original command
      ${
        if originalExecStart != null
        then ''
          exec ${originalExecStart}
        ''
        else ''
          echo "Error: No original ExecStart found for ${serviceName}"
          exit 1
        ''
      }
    '';

  # Generate drop-in package for a service
  makeDropinPackage = serviceName: serviceCfg: let
    hasWrapper = serviceCfg.execStartWrapper or null != null;
    wrapperCfg = serviceCfg.execStartWrapper;

    # Collect all credentials that need to be loaded and deduplicate
    allCredentials = unique (
      serviceCfg.loadCredentialEncrypted or []
      ++ (
        if hasWrapper
        then
          (
            wrapperCfg.envfiles
            ++ (attrValues wrapperCfg.environment)
          )
        else []
      )
    );

    # Generate the drop-in content
    dropinContent = ''
      [Service]
      ${concatMapStringsSep "\n" (
          cred: "LoadCredentialEncrypted=${cred}"
        )
        allCredentials}
      ${optionalString hasWrapper ''
        # Override ExecStart with our wrapper
        # First one empties so we avoide having multiple ExecStart directives
        ExecStart=
        ExecStart=${mkExecStartWrapper serviceName serviceCfg}
      ''}
    '';
  in
    # Generate a derivation with the drop in in it
    pkgs.runCommand "${serviceName}-credential-dropin" {
      preferLocalBuild = true;
      allowSubstitutes = false;
    } ''
      mkdir -p "$out/etc/systemd/system"
      mkdir -p "$out/etc/systemd/system/${serviceName}.service.d"

      echo '${dropinContent}' > "$out/etc/systemd/system/${serviceName}.service.d/50-credentials.conf"
    '';
in {
  options.gio.credentials = {
    enable =
      mkEnableOption "simplified encrypted credentials management"
      // {
        default = true;
      };

    services = mkOption {
      type = types.attrsOf (types.submodule ({
        name,
        config,
        ...
      }: {
        options = {
          loadCredentialEncrypted = mkOption {
            type = types.listOf types.str;
            default = [];
            description = ''
              List of credential names to load from the credential store.
              These will be available in $CREDENTIALS_DIRECTORY.
            '';
          };

          execStartWrapper = mkOption {
            type = types.nullOr (types.submodule {
              options = {
                envfiles = mkOption {
                  type = types.listOf types.str;
                  default = [];
                  description = ''
                    List of credential names that are environment files.
                    These will be sourced before the service starts.
                  '';
                };

                environment = mkOption {
                  type = types.attrsOf types.str;
                  default = {};
                  example = literalExpression ''
                    {
                      API_KEY = "api_key_credential";
                      DATABASE_PASSWORD = "db_password";
                    }
                  '';
                  description = ''
                    Attribute set mapping environment variable names to credential names.
                    Each credential will be read and exported as the specified environment variable.
                  '';
                };
              };
            });
            default = null;
            description = ''
              Configuration for wrapping ExecStart to load credentials.
              The original ExecStart will be automatically detected from the service.
            '';
          };

          credentialPath = mkOption {
            type = types.attrsOf types.str;
            readOnly = true;
            description = ''
              Helper attribute set that provides the runtime paths to credentials.
              For example, gio.credential.services.consul.credentialPath.encrypt will return
              "/run/credentials/consul.service/encrypt".
            '';
            default = let
              hasWrapper = config.execStartWrapper or null != null;
              allCredentialNames = unique (
                config.loadCredentialEncrypted or []
                ++ (
                  if hasWrapper
                  then
                    (
                      config.execStartWrapper.envfiles or []
                      ++ (attrValues config.execStartWrapper.environment or {})
                    )
                  else []
                )
              );
            in
              listToAttrs (map (credName: {
                  name = credName;
                  value = "/run/credentials/${name}.service/${credName}";
                })
                allCredentialNames);
          };
        };
      }));
      default = {};
      example = literalExpression ''
        {
          "atticd" = {
            loadCredentialEncrypted = [ "attic-envfile:/run/secrets/attic.env" ];
            execStartWrapper = {
              envfiles = [ "attic-envfile" ];
              environment = {
                ATTIC_SERVER_TOKEN = "attic_token";
              };
            };
          };
        }
      '';
      description = ''
        Attribute set mapping service names to credential configurations.
        This creates systemd drop-in files that augment existing services
        without modifying their original definitions.
      '';
    };
  };

  config = mkIf cfg.enable {
    # Load all of our drop ins into SystemD
    systemd.packages = mapAttrsToList makeDropinPackage cfg.services;
  };
}
