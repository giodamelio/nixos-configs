{
  root,
  inputs,
  homelab,
  ...
}: {
  inherit (homelab.machines.testing.deployment) hostname user sshUser;

  profiles.system = {
    path = inputs.deploy-rs.lib.x86_64-linux.activate.nixos root.nixosConfigurations.testing;
  };
}
