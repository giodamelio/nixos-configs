# comin — GitOps auto-deploy: poll this flake's main branch and rebuild.
# Converted from nix/modules/nixos/comin.nix. Host-attached (server hosts only);
# inert until a host includes it.
{inputs, ...}: {
  den.aspects.comin.nixos = {
    imports = [inputs.comin.nixosModules.comin];

    services.comin = {
      enable = true;
      remotes = [
        {
          name = "origin";
          url = "https://github.com/giodamelio/nixos-configs.git";
          branches.main.name = "main";
        }
      ];
      exporter.openFirewall = true;
    };
  };
}
