# TEMPORARY: mask gradient + its pull-deploy agent while carbon/gallium are
# stabilized (gradient leans on garage S3 over the NFS/wg mesh and its manual
# credstore secrets). Nothing in gradient.nix / deployed-apps.nix is deleted —
# remove this file to restore. Masking the units (not services.gradient.enable)
# keeps the module's frontend package + vhost evaluating and leaves the deployed
# apps (eater-of-feeds, yesman) running their last-deployed build; only the
# gradient-deployer agent that would redeploy them is masked.
_: {
  den.aspects.carbon.nixos = {lib, ...}: {
    systemd.services.gradient-server.enable = lib.mkForce false;
    systemd.services.gradient-worker.enable = lib.mkForce false;
    systemd.services.gradient-deployer.enable = lib.mkForce false;
  };
}
