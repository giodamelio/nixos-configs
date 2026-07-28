#!/usr/bin/env bash
# Boot-deploy carbon + gallium for the den migration. For each host: build the
# toplevel locally, push its closure to the `homelab` attic cache, then set it as
# the boot default on the remote via `nh os boot` (activates on NEXT reboot — it
# does NOT switch the running system). Reboot both hosts together afterwards so
# the regenerated wg-nfs tunnel comes up fresh on both.
#
# Run from the repo root inside the dev shell (nh + attic on PATH). Run the
# snapshot scripts FIRST.
set -euo pipefail

deploy_boot() {
  local host="$1" dest="$2"

  echo "==> [$host] building toplevel locally"
  # nh os build --diff never ".#nixosConfigurations.$host"
  nom build .#nixosConfigurations.$host.config.system.build.toplevel

  echo "==> [$host] pushing closure to attic (homelab)"
  attic push homelab result/

  echo "==> [$host] staging boot default on $dest (activates on next reboot)"
  nh os boot --ask --hostname "$host" --target-host "$dest" .

  rm -f result
  echo "==> [$host] staged for next boot"
  echo
}

deploy_boot carbon  server@carbon.gio.ninja
deploy_boot gallium server@gallium.gio.ninja

echo "Both hosts staged. Reboot carbon and gallium together to activate:"
echo "  ssh server@carbon.gio.ninja  sudo reboot"
echo "  ssh server@gallium.gio.ninja sudo reboot"
