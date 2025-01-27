{
  pkgs,
  modulesPath,
  myPkgs,
  ezModules,
  ...
}: {
  imports = [
    "${modulesPath}/virtualisation/qemu-vm.nix"
    ezModules.basic-packages
  ];

  users.users.server = {
    isNormalUser = true;
    extraGroups = ["wheel"];
    initialPassword = "test123";
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOKmSxFyT9n91A9dOpSCfl9kJj80KWFA6UvCtguT4S5b giodamelio@cadmium"
    ];
  };

  environment.systemPackages = [
    myPkgs.${pkgs.stdenv.system}.neovim
  ];

  services.openssh.enable = true;

  # Forward ssh port
  virtualisation.forwardPorts = [
    {
      from = "host";
      host.port = 2222;
      guest.port = 22;
    }
  ];

  networking = {
    useDHCP = true;
    hostName = "test-vm";
    firewall.enable = false;
  };

  system.stateVersion = "25.05";
  nixpkgs.hostPlatform = "x86_64-linux";
}
