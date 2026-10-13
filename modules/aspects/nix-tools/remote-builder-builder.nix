# remote-builder-builder — the builder side of the remote-build pair; clients
# (remote-builder-user) find builders through host.remoteBuilder.
{lib, ...}: let
  homelab = builtins.fromTOML (builtins.readFile ../../../homelab.toml);
  restrictKey = key: ''no-port-forwarding,no-X11-forwarding,no-agent-forwarding ${key}'';
in {
  den.schema.host.imports = [
    ({name, ...}: {
      options.remoteBuilder = {
        enable = lib.mkEnableOption "accepting remote Nix builds from remote-builder-user hosts";
        hostName = lib.mkOption {
          type = lib.types.str;
          default = "${name}.gio.ninja";
          description = "Address clients connect to over ssh-ng.";
        };
        systems = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          description = "Platforms this host builds for, e.g. [\"aarch64-linux\"].";
        };
        maxJobs = lib.mkOption {
          type = lib.types.ints.positive;
          default = 1;
          description = "Concurrent builds a client sends here.";
        };
        speedFactor = lib.mkOption {
          type = lib.types.ints.positive;
          default = 1;
          description = "Preference among builders for the same system; higher wins.";
        };
        supportedFeatures = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [];
          description = "System features builds may require here (kvm, nixos-test, big-parallel, ...).";
        };
      };
    })
  ];

  den.aspects.remote-builder-builder.nixos = {
    host,
    lib,
    ...
  }:
    lib.mkIf host.remoteBuilder.enable {
      users.users.nix-remote-builder = {
        isNormalUser = true;
        home = "/home/nix-remote-builder";
        openssh.authorizedKeys.keys = map restrictKey homelab.remote_builder_keys;
      };

      nix.settings.trusted-users = ["nix-remote-builder"];

      # Limit remote builder to half the CPU so local work isn't starved
      systemd.slices."user-nix\\x2dremote\\x2dbuilder" = {
        sliceConfig = {
          CPUQuota = "600%";
        };
      };
    };
}
