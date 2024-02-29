{root, ...}: {
  lib,
  pkgs,
  config,
  ...
}: let
  cfg = config.services.acme-redirect;
  acmeRedirect = root.packages.acme-redirect {inherit pkgs;};

  certType = lib.types.submodule {
    options = {
      dns_names = lib.mkOption {
        type = lib.types.listOf lib.types.str;
      };
    };
  };
in {
  options.services.acme-redirect = {
    enable = lib.mkEnableOption "lego acme security fetcher";

    package = lib.mkPackageOption pkgs "acme-redirect" {
      default = [acmeRedirect];
    };

    email = lib.mkOption {
      type = lib.types.str;
    };

    acmeUrl = lib.mkOption {
      type = lib.types.str;
      default = "https://acme-staging-v02.api.letsencrypt.org/directory";
    };

    certs = lib.mkOption {
      type = lib.types.attrsOf certType;
      default = {};
    };
  };

  config = lib.mkIf cfg.enable {};
}
