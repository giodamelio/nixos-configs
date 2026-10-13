# remote-builder-user — offload builds over ssh-ng to every host with
# remoteBuilder.enable; Nix routes each derivation by its system and features.
{
  lib,
  config,
  ...
}: let
  base64 = import ./_base64.nix {inherit lib;};
  builders = lib.pipe config.den.hosts [
    (lib.concatMapAttrs (_system: hosts: hosts))
    (lib.filterAttrs (_name: host: host.remoteBuilder.enable))
  ];
in {
  den.schema.host.imports = [
    ({config, ...}: {
      options.useRemoteBuilders = lib.mkOption {
        type = lib.types.bool;
        # aarch64 hosts are Pis and other slow boards; builders build for themselves.
        default = config.system == "aarch64-linux" && !config.remoteBuilder.enable;
        description = "Offload builds to the fleet's remote builders. Needs /root/.ssh/nix-remote-builder, listed in homelab.toml remote_builder_keys.";
      };
    })
  ];

  den.aspects.remote-builder-user.nixos = {host, ...}:
    lib.mkIf host.useRemoteBuilders {
      nix.buildMachines = lib.mapAttrsToList (name: builder:
        lib.throwIf (builder.ssh.hostKey == null) "remote-builder-user: builder ${name} has no ssh.hostKey to pin"
        {
          inherit (builder.remoteBuilder) hostName systems maxJobs speedFactor supportedFeatures;
          protocol = "ssh-ng";
          sshUser = "nix-remote-builder";
          sshKey = "/root/.ssh/nix-remote-builder";
          publicHostKey = base64.toBase64 builder.ssh.hostKey;
        }) (removeAttrs builders [host.name]);

      nix.distributedBuilds = true;
      # Builders fetch inputs from the caches themselves instead of the client
      # uploading them, which matters most for the Pis.
      nix.settings.builders-use-substitutes = true;
    };
}
