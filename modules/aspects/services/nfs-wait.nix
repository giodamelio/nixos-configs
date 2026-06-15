_: {
  # Bridge: a service that declares `mounts = [<nfs mount name>]` gets its systemd
  # unit ordered after that mount's readiness target — no escaped .mount name to
  # remember. Dependency direction services -> nfs (fleet.nfs stays standalone).
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
        requires = map (targetOf svcName) svc.mounts;
      })
    withMounts;
  };
}
