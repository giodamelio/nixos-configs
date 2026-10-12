_: {
  # Bridge: a service that declares `mounts = [<nfs mount name>]` gets its systemd
  # unit bound to that mount's readiness target — no escaped .mount name to
  # remember. BindsTo, not Requires: the service also stops if the mount goes
  # away, instead of writing into the empty mountpoint. Dependency direction
  # services -> nfs (fleet.nfs stays standalone).
  den.aspects.services-nfs-wait.nixos = {
    host,
    fleet,
    lib,
    ...
  }: let
    mounts = fleet.nfs.mounts;
    withMounts = lib.filterAttrs (_name: svc: svc.mounts != []) (host.services or {});
    targetOf = svcName: m:
      if mounts ? ${m}
      then "nfs-${m}.target"
      else throw "services-nfs-wait: ${host.name} service ${svcName} needs unknown nfs mount '${m}'";
  in {
    systemd.services = lib.mapAttrs' (svcName: svc:
      lib.nameValuePair svc.unit {
        after = map (targetOf svcName) svc.mounts;
        bindsTo = map (targetOf svcName) svc.mounts;
      })
    withMounts;
  };
}
