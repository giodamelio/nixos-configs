# Script that makes ca.json's managed JWK provisioners match `provisioners`
# (name -> list of `step ca provisioner` flags), creating each one's key pair and
# password on first sight. Provisioners not listed are never touched. `settings`
# is deep-merged into ca.json last. Shared by strontium's
# step-ca-provisioners.service and the nfs-cert and mtls VM tests.
{
  pkgs,
  lib,
}: {
  caDir,
  group,
  provisioners,
  settings ? {},
}: let
  caJson = "${caDir}/ca.json";
  # The CLI only edits ca.json directly when it cannot reach the CA's admin API;
  # aim it at a closed port so it always takes that offline path.
  offline = "--ca-url https://127.0.0.1:1 --root ${caDir}/root.crt --ca-config ${caJson}";

  ensure = name: flags: let
    dir = "${caDir}/provisioners/${name}";
    flagStr = lib.escapeShellArgs flags;
  in ''
    install -d -m 0700 ${dir}
    if [ ! -s ${dir}/password ]; then
      (umask 077 && head -c 32 /dev/urandom | base64 > ${dir}/password)
    fi
    if jq -e --arg n ${name} '.authority.provisioners[]? | select(.name == $n)' ${caJson} >/dev/null; then
      step ca provisioner update ${name} ${flagStr} ${offline}
    else
      step ca provisioner add ${name} --type JWK --create \
        --password-file ${dir}/password ${flagStr} ${offline}
    fi
  '';
in
  pkgs.writeShellApplication {
    name = "step-ca-provisioners";
    runtimeInputs = [pkgs.step-cli pkgs.jq pkgs.coreutils];
    text = ''
      STEPPATH="$(mktemp -d)"
      export STEPPATH
      trap 'rm -rf "$STEPPATH"' EXIT
      ${lib.concatStrings (lib.mapAttrsToList ensure provisioners)}
      # Sorting keeps reruns byte-identical: `provisioner update` reorders both
      # the keys and the provisioner list.
      jq --sort-keys --argjson s ${lib.escapeShellArg (builtins.toJSON settings)} \
        '. * $s | .authority.provisioners |= sort_by(.name)' ${caJson} > ${caJson}.new
      mv ${caJson}.new ${caJson}
      # The CLI rewrites ca.json; restore the mode step-ca reads it with.
      chown root:${group} ${caJson}
      chmod 0640 ${caJson}
    '';
  }
