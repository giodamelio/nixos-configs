# The NFS host certificate from strontium's step-ca (`nfs` JWK provisioner).
# Enrolled once: `ca-enroll-host <host> nfs` on strontium prints a command that
# drops a single-use token into enroll-token, which the path unit consumes.
# Renewed daily by proving possession of the current cert; a cert that lapses
# (host off for more than its 7-day lifetime) needs a fresh enrollment.
_: let
  caUrl = "https://ca.gio.ninja";
  dir = "/var/lib/step-nfs";
in {
  den.aspects.nfs.nixos = {
    fleet,
    host,
    pkgs,
    lib,
    ...
  }: let
    fqdn = "${host.name}.${fleet.dns.domain}";
    stepArgs = "--ca-url ${caUrl} --root ${fleet.nfs.caRoot}";

    enroll = pkgs.writeShellApplication {
      name = "nfs-cert-enroll";
      runtimeInputs = [pkgs.step-cli pkgs.systemd];
      text = ''
        token="$(cat ${dir}/enroll-token)"
        # Remove it before using it: a failed enrollment must not re-trigger the
        # path unit in a loop, and the token is single-use either way.
        rm -f ${dir}/enroll-token
        step ca certificate --token "$token" ${stepArgs} --force \
          ${fqdn} ${dir}/cert.pem ${dir}/key.pem
        systemctl restart tlshd.service
      '';
    };

    renew = pkgs.writeShellApplication {
      name = "nfs-cert-renew";
      runtimeInputs = [pkgs.step-cli pkgs.systemd];
      text = ''
        # Flags first: `step ca renew` stops parsing flags at the first path.
        step ca renew --force ${stepArgs} ${dir}/cert.pem ${dir}/key.pem
        systemctl try-restart tlshd.service
      '';
    };
  in
    lib.mkIf host.nfs.enable {
      environment.systemPackages = [pkgs.step-cli];
      systemd.tmpfiles.rules = ["d ${dir} 0700 root root - -"];

      systemd.paths.nfs-cert-enroll = {
        description = "Enroll the NFS certificate once a token is dropped";
        wantedBy = ["multi-user.target"];
        pathConfig.PathExists = "${dir}/enroll-token";
      };
      systemd.services.nfs-cert-enroll = {
        description = "Enroll this host's NFS certificate via step-ca";
        after = ["network-online.target"];
        wants = ["network-online.target"];
        serviceConfig = {
          Type = "oneshot";
          ExecStart = lib.getExe enroll;
        };
      };

      systemd.services.nfs-cert-renew = {
        description = "Renew this host's NFS certificate via step-ca";
        after = ["network-online.target"];
        wants = ["network-online.target"];
        # Dormant (not failed) until the host is enrolled.
        unitConfig.ConditionPathExists = "${dir}/cert.pem";
        serviceConfig = {
          Type = "oneshot";
          ExecStart = lib.getExe renew;
        };
      };
      systemd.timers.nfs-cert-renew = {
        description = "Daily NFS certificate renewal";
        wantedBy = ["timers.target"];
        timerConfig = {
          OnCalendar = "daily";
          Persistent = true;
          RandomizedDelaySec = "1h";
        };
      };
    };
}
