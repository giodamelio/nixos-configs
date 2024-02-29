_: {
  lib,
  pkgs,
  config,
  ...
}: let
  cfg = config.security.lego;

  basePath = "/var/lib/lego";

  certType = lib.types.submodule {
    options = {
      acmeServer = lib.mkOption {
        type = lib.types.enum [
          "letsencrypt"
          "letsencrypt-staging"
        ];
        default = "letsencrypt-staging";
      };

      cert_file = lib.mkOption {
        type = lib.types.path;
        readOnly = true;
      };
      key_file = lib.mkOption {
        type = lib.types.path;
        readOnly = true;
      };
    };
  };
in {
  options.security.lego = {
    enable = lib.mkEnableOption "lego acme security fetcher";

    acceptTerms = lib.mkOption {
      type = lib.types.bool;
      default = false;
    };

    email = lib.mkOption {
      type = lib.types.str;
    };

    certs = lib.mkOption {
      type = lib.types.attrsOf certType;
      default = {};
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.acceptTerms;
        message = "You must accept the LetsEncrypt terms of service";
      }
    ];

    # Build a set of systemd services
    systemd.services =
      lib.attrsets.concatMapAttrs (domain: _options: {
        "lego-${domain}-obtain-certificate" = {
          description = "Obtain a certificate for ${domain}";
          wantedBy = ["default.target"];
          serviceConfig = {
            Type = "oneshot";
            ImportCredential = "CLOUDFLARE_API_TOKEN";
          };
          unitConfig = {
            # Note negation of the path
            ConditionPathExists = "!${basePath}/certificates/${domain}.json";
            # TODO: why doesn't this work?
            # AssertCredential = "test-cred";
          };
          environment = {
            LEGO_PATH = basePath;
            CLOUDFLARE_DNS_API_TOKEN_FILE = "%d/CLOUDFLARE_API_TOKEN";
          };
          script = ''
            ${pkgs.lego}/bin/lego \
              --server=https://acme-staging-v02.api.letsencrypt.org/directory \
              --email ${cfg.email} \
              --accept-tos \
              --dns cloudflare \
              --domains ${domain} \
              run
          '';
        };

        "lego-${domain}-renew-certificate" = {
          description = "Renew a certificate for ${domain}";
          wantedBy = ["default.target"];
          after = ["lego-${domain}-obtain-certificate.service"];
          serviceConfig = {
            Type = "oneshot";
            ImportCredential = "CLOUDFLARE_API_TOKEN";
          };
          unitConfig = {
            ConditionPathExists = "${basePath}/certificates/${domain}.json";
            # TODO: why doesn't this work?
            # AssertCredential = "test-cred";
          };
          environment = {
            LEGO_PATH = basePath;
            CLOUDFLARE_DNS_API_TOKEN_FILE = "%d/CLOUDFLARE_API_TOKEN";
          };
          script = ''
            ${pkgs.lego}/bin/lego \
              --server=https://acme-staging-v02.api.letsencrypt.org/directory \
              --email ${cfg.email} \
              --accept-tos \
              --dns cloudflare \
              --domains ${domain} \
              renew \
              --days 30
          '';
        };
      })
      cfg.certs;

    # Build a set of systemd services
    systemd.timers =
      lib.attrsets.concatMapAttrs (domain: _options: {
        "lego-${domain}-renew-certificate" = {
          description = "Try to renew certificate for ${domain} every day";
          wantedBy = ["timers.target"];
          timerConfig = {
            OnCalendar = "daily";
            Persistent = "true";
            RandomizedDelaySec = 3600; # 1 hour
          };
        };
      })
      cfg.certs;

    # Set the read only path values so other modules can find the files
    # security.lego.certs = lib.attrsets.concatMapAttrs (domain: options: {
    #   a = "aaa";
    # } // options) cfg.certs;
  };
}
