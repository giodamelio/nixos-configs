# remote-builder-user — offload builds to cadmium over ssh-ng. Converted from
# nix/modules/nixos/remote-builder-user.nix.
_: {
  den.aspects.remote-builder-user.nixos = {
    nix.buildMachines = [
      {
        hostName = "cadmium.gio.ninja";
        protocol = "ssh-ng";
        sshUser = "nix-remote-builder";
        sshKey = "/root/.ssh/nix-remote-builder";
        systems = ["x86_64-linux"];
        maxJobs = 8;
        speedFactor = 4;
        supportedFeatures = ["nixos-test" "benchmark" "big-parallel" "kvm"];
      }
    ];

    nix.distributedBuilds = true;
  };
}
