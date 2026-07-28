# A Telegraf modular service (NixOS RFC 163). Models ONE telegraf process;
# instantiate it via `gio.telegraf.instances.<name>`. Upstream this file would be
# `service.nix`; the leading `_` only keeps import-tree from loading it as a
# flake-parts module.
#
# Non-module deps arrive via importApply so the module stays self-contained
# (see modules/aspects/server/caddy/_service.nix for the same pattern).
{pkgs}: {
  lib,
  config,
  options,
  ...
}: let
  inherit (lib) mkOption types;
  cfg = config;

  settingsFormat = pkgs.formats.toml {};

  generatedConfig = settingsFormat.generate "telegraf.conf" cfg.settings;
in {
  # https://nixos.org/manual/nixos/unstable/#modular-services
  _class = "service";

  options = {
    enable =
      lib.mkEnableOption "this Telegraf instance"
      // {default = true;};

    package = mkOption {
      type = types.package;
      default = pkgs.telegraf;
      defaultText = lib.literalExpression "pkgs.telegraf";
      description = "Telegraf package to run.";
    };

    user = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = ''
        User to run as. `null` runs under a systemd `DynamicUser`. Set
        `"root"` for instances whose inputs need privileged access (NVMe
        passthrough, /dev/zfs).
      '';
    };

    group = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "Group to run as. Only meaningful together with `user`.";
    };

    settings = mkOption {
      inherit (settingsFormat) type;
      default = {};
      description = ''
        Telegraf configuration as Nix, rendered to TOML. Plugin lists are
        attrsets of lists, mirroring TOML's `[[inputs.cpu]]`, e.g.
        `inputs.cpu = [{ totalcpu = true; }]`.
      '';
      example = lib.literalExpression ''
        {
          agent.interval = "60s";
          inputs.cpu = [{ totalcpu = true; }];
          outputs.http = [{ url = "https://example.com"; }];
        }
      '';
    };

    configFile = mkOption {
      type = types.path;
      default = generatedConfig;
      defaultText = "A telegraf.conf generated from this instance's `settings`.";
      description = "Override the config file this instance runs.";
    };

    path = mkOption {
      type = types.listOf types.package;
      default = [];
      description = "Extra packages on PATH, for `inputs.exec` commands.";
    };
  };

  config =
    {
      # The store path is passed to --config directly rather than going through
      # the framework's configData (which would symlink it into /etc): the config
      # holds no secrets, and a direct path keeps the running command traceable
      # straight back to its derivation.
      process.argv = [(lib.getExe cfg.package) "--config" cfg.configFile];
    }
    // lib.optionalAttrs (options ? systemd) {
      systemd.service = {
        enable = lib.mkDefault cfg.enable;
        inherit (cfg) path;
        restartTriggers = [cfg.configFile];

        # wantedBy, Type, Restart and RestartSec already come from the framework
        # (nixos/modules/system/service/systemd/service.nix) as mkDefaults —
        # repeating them here would collide at equal priority, not override.
        serviceConfig = {
          DynamicUser = lib.mkDefault (cfg.user == null);
          User = lib.mkIf (cfg.user != null) cfg.user;
          Group = lib.mkIf (cfg.group != null) cfg.group;

          # Defaults an instance can relax; telegraf itself writes nothing.
          NoNewPrivileges = lib.mkDefault true;
          ProtectHome = lib.mkDefault true;
          ProtectSystem = lib.mkDefault "strict";
          PrivateTmp = lib.mkDefault true;
          # Inputs that enumerate interfaces (inputs.net, inputs.netstat) talk
          # netlink and need AF_NETLINK added on the instance.
          RestrictAddressFamilies = lib.mkDefault ["AF_INET" "AF_INET6" "AF_UNIX"];
        };
      };
    };

  meta.maintainers = [lib.maintainers.giodamelio];
}
