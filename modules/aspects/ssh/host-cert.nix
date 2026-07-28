# Host-CA trust: teaches every host's ssh client to verify peers' step-ca-signed
# host certs via `@cert-authority`, plus fleet-wide host/user cert revocation
# (KRL). The certs themselves are served by the host at runtime (ssh-host-cert-renew,
# from /var/lib/step-ssh) — nothing is committed here.
{
  lib,
  config,
  ...
}: let
  inherit (import ./_types.nix {inherit lib;}) enabledHostsOf;

  dataDir = config.fleet.ssh.dataDir;
  hostCaPath = dataDir + "/host-ca.pub";
  hasHostCa = builtins.pathExists hostCaPath;

  # host-ca.pub may hold multiple CA keys (one per line); clients trust each.
  hostCaKeys = lib.pipe hostCaPath [
    builtins.readFile
    (lib.splitString "\n")
    (map (lib.removeSuffix "\r"))
    (builtins.filter (line: line != ""))
  ];

  # Bare names make plain `ssh carbon` cert-verified too (the @cert-authority
  # pattern list is exact-match) — one per enrolled den host.
  enrolledNames = builtins.attrNames (enabledHostsOf (lib.concatMapAttrs (_system: hosts: hosts) config.den.hosts));
in {
  den.aspects.ssh-host-cert.nixos = {
    fleet,
    host,
    pkgs,
    lib,
    ...
  }: let
    revoked = fleet.ssh.revocations;

    # KRLs only need the CA public key (-s).
    mkKrl = name: caPubFile: specs:
      pkgs.runCommand "ssh-krl-${name}" {} ''
        cat > spec <<'EOF'
        ${lib.concatStringsSep "\n" specs}
        EOF
        ${pkgs.openssh}/bin/ssh-keygen -k -f $out -s ${caPubFile} spec
      '';
  in
    lib.mkIf host.ssh.enable (lib.mkMerge [
      (lib.mkIf hasHostCa {
        programs.ssh.knownHosts = lib.listToAttrs (lib.imap0 (i: key:
          lib.nameValuePair "gio-ninja-host-ca-${toString i}" {
            certAuthority = true;
            hostNames = ["*.gio.ninja"] ++ enrolledNames;
            publicKey = key;
          })
        hostCaKeys);
      })

      (lib.mkIf (revoked.users != []) {
        services.openssh.settings.RevokedKeys = "${mkKrl "users" (dataDir + "/user-ca.pub") revoked.users}";
      })

      (lib.mkIf (revoked.hosts != []) {
        programs.ssh.extraConfig = ''
          RevokedHostKeys ${mkKrl "hosts" (dataDir + "/host-ca.pub") revoked.hosts}
        '';
      })
    ]);
}
