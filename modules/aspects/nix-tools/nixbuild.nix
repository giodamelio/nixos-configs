# nixbuild.net as a remote builder. Shared and opt-in: include it on any host
# that should offload builds. Defaults to aarch64 only — the point is to avoid
# qemu-emulated ARM builds, which take hours for large Rust trees.
_: {
  den.aspects.nixbuild.nixos = {
    lib,
    config,
    ...
  }: let
    cfg = config.gio.nixbuild;
  in {
    options.gio.nixbuild = {
      host = lib.mkOption {
        type = lib.types.str;
        default = "eu.nixbuild.net";
        description = "nixbuild.net endpoint to build on.";
      };

      identityFile = lib.mkOption {
        type = lib.types.str;
        default = "/root/.ssh/nixbuild_ed25519";
        description = ''
          SSH private key registered with nixbuild.net. Needs to be root-readable
          (nix-daemon dispatches builds as root) and passphraseless — the daemon
          runs with no HOME, so it has no agent and resolves nothing by
          convention. It does NOT have to live under /root; a path in a user's
          ~/.ssh works, since the daemon is unsandboxed.
        '';
      };

      systems = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = ["aarch64-linux"];
        description = ''
          Systems to dispatch to nixbuild.net. ARM only by default so native
          x86_64 builds stay local; add "x86_64-linux" to offload those too.
        '';
      };
    };

    config = {
      programs.ssh.extraConfig = ''
        Host ${cfg.host}
          PubkeyAcceptedKeyTypes ssh-ed25519
          ServerAliveInterval 60
          IdentityFile ${cfg.identityFile}
      '';

      programs.ssh.knownHosts.nixbuild = {
        hostNames = [cfg.host];
        publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPIQCZc54poJ8vqawd8TraNryQeJnvH1eLpIDgbiqymM";
      };

      nix = {
        distributedBuilds = true;
        buildMachines = [
          {
            hostName = cfg.host;
            inherit (cfg) systems;
            # Also passed as `ssh -i`, so dispatch doesn't depend on ssh_config
            # being picked up — nix-daemon runs with no HOME, so nothing resolves
            # by convention.
            sshKey = cfg.identityFile;
            # nixbuild.net schedules each build in its own machine, so there is
            # no reason to throttle from our side.
            maxJobs = 100;
            supportedFeatures = ["benchmark" "big-parallel"];
          }
        ];
      };

      # Let nixbuild fetch dependencies from the public caches itself instead of
      # us uploading the whole closure over SSH.
      nix.settings.builders-use-substitutes = true;

      # binfmt otherwise adds its emulated systems to extra-platforms, which makes
      # Nix build them locally under qemu and ignore the remote builder entirely.
      # Emulation stays available for *running* foreign binaries.
      boot.binfmt.addEmulatedSystemsToNixSandbox = lib.mkDefault false;
    };
  };
}
