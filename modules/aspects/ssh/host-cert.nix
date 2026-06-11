{lib, ...}: let
  dataDir = ./data;
  hostCaPath = dataDir + "/host-ca.pub";
  hasHostCa = builtins.pathExists hostCaPath;

  # Bare names make plain `ssh carbon` cert-verified too (the
  # @cert-authority pattern list is exact-match).
  enrolledNames = lib.pipe (dataDir + "/certs") [
    builtins.readDir
    builtins.attrNames
    (builtins.filter (lib.hasSuffix "-cert.pub"))
    (map (lib.removeSuffix "-cert.pub"))
  ];
in {
  den.aspects.ssh-host-cert.nixos = {
    fleet,
    host,
    pkgs,
    lib,
    ...
  }: let
    certPath = dataDir + "/certs/${host.name}-cert.pub";
    hasCert = builtins.pathExists certPath;
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
        programs.ssh.knownHosts.gio-ninja-host-ca = {
          certAuthority = true;
          hostNames = ["*.gio.ninja"] ++ enrolledNames;
          publicKey = lib.removeSuffix "\n" (builtins.readFile hostCaPath);
        };
      })

      (lib.mkIf hasCert {
        services.openssh.settings.HostCertificate = "/etc/ssh/ssh_host_ed25519_key-cert.pub";
        environment.etc."ssh/ssh_host_ed25519_key-cert.pub" = {
          # readFile, not `.source`: depend on content, never the flake path.
          text = builtins.readFile certPath;
          mode = "0644";
        };
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
