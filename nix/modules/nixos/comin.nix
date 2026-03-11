{inputs, ...}: {
  imports = [
    inputs.comin.nixosModules.comin
  ];

  services.comin = {
    enable = true;
    remotes = [
      {
        name = "origin";
        url = "https://github.com/giodamelio/nixos-configs.git";
        branches.main.name = "main";
      }
    ];
    exporter = {
      openFirewall = true;
    };
  };
}
