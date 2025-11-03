{
  config,
  lib,
  ...
}:
with lib; let
  cfg = config.gio.loadCredentialEncrypted;
in {
  options.gio.loadCredentialEncrypted = {
    enable =
      mkEnableOption "simplified encrypted credentials management"
      // {
        default = true;
      };

    services = mkOption {
      type = types.attrsOf (types.listOf types.str);
      default = {};
      example = literalExpression ''
        {
          "unifi-poller" = [ "garage_rpc_secret" "api_key" ];
          "nginx" = [ "ssl_cert" ];
        }
      '';
      description = ''
        Attribute set mapping service names to lists of credential names.
        Each credential will be loaded from the credential store directory.
      '';
    };
  };

  config = mkIf cfg.enable {
    systemd.services =
      mapAttrs (_serviceName: credentialNames: {
        serviceConfig.LoadCredentialEncrypted = credentialNames;
      })
      cfg.services;
  };
}
