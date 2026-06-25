# A Caddy modular service (NixOS RFC 163). Models ONE caddy server; instantiate
# it via `system.services.<name>` (the thin gio.caddy aspect does this per
# instance). Upstream this file would be `service.nix`; the leading `_` only keeps
# import-tree from loading it as a flake-parts module.
#
# Non-module deps are passed via importApply so the module stays self-contained
# and Nixpkgs-version agnostic (README-modular-services.md).
{pkgs}: {
  lib,
  config,
  options,
  ...
}: let
  inherit (lib) mkOption types optionalString concatStringsSep concatMapStringsSep;
  cfg = config;

  settingsFormat = pkgs.formats.json {};

  # ACME-host file certs: a portable service can't touch `security.acme.certs`, so
  # we reference the conventional default cert directory; the host provisions it.
  mkVHostConf = hostOpts: let
    sslCertDir = "/var/lib/acme/${hostOpts.useACMEHost}";
  in ''
    ${hostOpts.hostName} ${concatStringsSep " " hostOpts.serverAliases} {
      ${optionalString (hostOpts.listenAddresses != []) "bind ${concatStringsSep " " hostOpts.listenAddresses}"}
      ${optionalString (hostOpts.useACMEHost != null) "tls ${sslCertDir}/cert.pem ${sslCertDir}/key.pem"}
      ${optionalString (hostOpts.logFormat != null) ''
      log {
        ${hostOpts.logFormat}
      }
    ''}

      ${hostOpts.extraConfig}
    }
  '';

  configFile =
    if cfg.settings != {}
    then settingsFormat.generate "caddy.json" cfg.settings
    else let
      Caddyfile = pkgs.writeTextDir "Caddyfile" ''
        {
          ${cfg.globalConfig}
        }
        ${cfg.extraConfig}
        ${concatMapStringsSep "\n" mkVHostConf (lib.attrValues cfg.virtualHosts)}
      '';

      Caddyfile-formatted =
        pkgs.runCommand "Caddyfile-formatted" {
          nativeBuildInputs = [cfg.package];
        } ''
          mkdir -p $out
          cp --no-preserve=mode ${Caddyfile}/Caddyfile $out/Caddyfile
          caddy fmt --overwrite $out/Caddyfile
        '';
    in "${
      if pkgs.stdenv.buildPlatform == pkgs.stdenv.hostPlatform
      then Caddyfile-formatted
      else Caddyfile
    }/Caddyfile";

  configPath = config.configData."caddy_config".path;
in {
  # https://nixos.org/manual/nixos/unstable/#modular-services
  _class = "service";

  options = {
    enable =
      lib.mkEnableOption "this Caddy server"
      // {default = true;};

    package = mkOption {
      type = types.package;
      default = pkgs.caddy;
      defaultText = lib.literalExpression "pkgs.caddy";
      description = "Caddy package to run. Override per instance with `pkgs.caddy.withPlugins` to give a server its own plugin set.";
    };

    user = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "User to run as. `null` runs the service under a systemd `DynamicUser`.";
    };

    group = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "Group to run as. Only meaningful together with `user`.";
    };

    dataDir = mkOption {
      type = types.path;
      default = "/var/lib/caddy";
      description = "Data directory (Caddy's XDG home; holds ACME state). Give each instance its own.";
    };

    logDir = mkOption {
      type = types.path;
      default = "/var/log/caddy";
      description = "Directory for access logs. Give each instance its own.";
    };

    logFormat = mkOption {
      type = types.lines;
      default = "level ERROR\n";
      description = "Default logger config; see <https://caddyserver.com/docs/caddyfile/options#log>.";
    };

    configFile = mkOption {
      type = types.path;
      default = configFile;
      defaultText = "A Caddyfile generated from this service's options.";
      description = "Override the config file Caddy runs.";
    };

    adapter = mkOption {
      type = types.nullOr types.str;
      default =
        if (cfg.configFile != configFile) || (baseNameOf cfg.configFile) == "Caddyfile"
        then "caddyfile"
        else null;
      defaultText = lib.literalExpression ''if (configFile != generated) || baseNameOf configFile == "Caddyfile" then "caddyfile" else null'';
      description = "Config adapter (`--adapter`). `null` for native JSON config.";
    };

    resume = mkOption {
      type = types.bool;
      default = false;
      description = "Use Caddy's last autosaved config in preference to `--config`.";
    };

    globalConfig = mkOption {
      type = types.lines;
      default = "";
      description = "Lines for the Caddyfile global options block.";
    };

    extraConfig = mkOption {
      type = types.lines;
      default = "";
      description = "Lines appended to the generated Caddyfile (snippets, extra sites).";
    };

    email = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "ACME account email.";
    };

    acmeCA = mkOption {
      type = types.nullOr types.str;
      default = null;
      example = "https://acme-staging-v02.api.letsencrypt.org/directory";
      description = "ACME CA directory URL. `null` enables Caddy's issuer fallback.";
    };

    httpPort = mkOption {
      type = types.nullOr types.port;
      default = 80;
      description = "Default HTTP port.";
    };

    httpsPort = mkOption {
      type = types.nullOr types.port;
      default = 443;
      description = "Default HTTPS (and HTTP/3) port.";
    };

    enableReload = mkOption {
      type = types.bool;
      default = true;
      description = "Reload instead of restarting Caddy when the config changes (needs the admin API on).";
    };

    adminEndpoint = mkOption {
      type = types.nullOr types.str;
      default = null;
      example = "unix//run/caddy/admin.sock";
      description = ''
        Address for Caddy's admin API (the global `admin` directive). `null` keeps
        Caddy's default (`localhost:2019`). Set a unique value per server when
        running several Caddy processes on one host, or `"off"` to disable it
        (which also disables {option}`enableReload`).
      '';
    };

    settings = mkOption {
      inherit (settingsFormat) type;
      default = {};
      description = "Native JSON config (<https://caddyserver.com/docs/json/>). Takes precedence over the Caddyfile options; upstream recommends a Caddyfile instead.";
    };

    virtualHosts = mkOption {
      type = types.attrsOf (types.submodule (import "${pkgs.path}/nixos/modules/services/web-servers/caddy/vhost-options.nix" {cfg = config;}));
      default = {};
      description = "Declarative virtual hosts (the upstream `services.caddy.virtualHosts` submodule).";
    };
  };

  config =
    {
      assertions = [
        {
          assertion = (cfg.configFile == configFile) -> (cfg.adapter == "caddyfile" || cfg.adapter == null);
          message = "caddy modular service: to use an adapter other than 'caddyfile', provide your own `configFile`.";
        }
      ];

      globalConfig = ''
        ${optionalString (cfg.adminEndpoint != null) "admin ${cfg.adminEndpoint}"}
        ${optionalString (cfg.email != null) "email ${cfg.email}"}
        ${optionalString (cfg.acmeCA != null) "acme_ca ${cfg.acmeCA}"}
        ${optionalString (cfg.httpPort != null && cfg.httpPort != 80) "http_port ${toString cfg.httpPort}"}
        ${optionalString (cfg.httpsPort != null && cfg.httpsPort != 443) "https_port ${toString cfg.httpsPort}"}
        log {
          ${cfg.logFormat}
        }
      '';

      # Config lives in /etc (via the framework's configData) so `caddy reload` and
      # rebuilds pick up changes; this mirrors the traditional module's /etc placement.
      configData."caddy_config".source = cfg.configFile;

      process.argv =
        [(lib.getExe cfg.package) "run" "--config" configPath]
        ++ lib.optionals (cfg.adapter != null) ["--adapter" cfg.adapter]
        ++ lib.optional cfg.resume "--resume";
    }
    // lib.optionalAttrs (options ? systemd) {
      systemd.service = {
        enable = lib.mkDefault cfg.enable;
        wantedBy = lib.mkDefault ["multi-user.target"];
        startLimitIntervalSec = 14400;
        startLimitBurst = 10;
        reloadTriggers = lib.optional cfg.enableReload cfg.configFile;
        restartTriggers = lib.optional (!cfg.enableReload) cfg.configFile;

        serviceConfig = {
          ExecReload = lib.optional cfg.enableReload "${lib.getExe cfg.package} reload --config ${configPath} ${optionalString (cfg.adapter != null) "--adapter ${cfg.adapter}"} --force";
          Restart = "on-failure";
          RestartPreventExitStatus = 1;
          RestartSec = "5s";

          DynamicUser = cfg.user == null;
          User = lib.mkIf (cfg.user != null) cfg.user;
          Group = lib.mkIf (cfg.group != null) cfg.group;

          ReadWritePaths = [cfg.dataDir cfg.logDir];
          StateDirectory = lib.mkIf (lib.hasPrefix "/var/lib/" cfg.dataDir) [(lib.removePrefix "/var/lib/" cfg.dataDir)];
          LogsDirectory = lib.mkIf (lib.hasPrefix "/var/log/" cfg.logDir) [(lib.removePrefix "/var/log/" cfg.logDir)];

          NoNewPrivileges = true;
          PrivateDevices = true;
          ProtectHome = true;
        };

        # Caddy v2 stores state under XDG dirs; point them at the data dir.
        environment = {
          XDG_CONFIG_HOME = cfg.dataDir;
          XDG_DATA_HOME = cfg.dataDir;
        };
      };
    };

  meta.maintainers = [lib.maintainers.giodamelio];
}
