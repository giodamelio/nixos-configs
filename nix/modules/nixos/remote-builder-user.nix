{
  nix.buildMachines = [
    {
      hostName = "cadmium.gio.ninja";
      sshUser = "nix-remote-builder";
      sshKey = "/root/.ssh/nix-remote-builder";
      systems = ["x86_64-linux"];
      maxJobs = 8;
      speedFactor = 4;
      supportedFeatures = ["nixos-test" "benchmark" "big-parallel" "kvm"];
    }
  ];

  nix.distributedBuilds = true;
}
