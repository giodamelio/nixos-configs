# Per-host SSH host-cert self-renewal against strontium's step-ca (SSHPOP).
# A host is enrolled once (a single-use token mints its first cert — see
# `ca-enroll-host` on strontium); from then on a daily timer renews the cert by
# proving possession of the current one. No secret is ever distributed, and
# nothing per-host is committed to the flake. Runtime CA reachability matters
# only for renewal (buffered by the 30d validity), never for login or
# steady-state host verification. See docs/pi-ca-secrets-plan.md.
{config, ...}: let
  dataDir = config.fleet.ssh.dataDir;
  rootAnchor = dataDir + "/ca-root.crt";
  hasRootAnchor = builtins.pathExists rootAnchor;

  caUrl = "https://ca.gio.ninja";
  liveCert = "/var/lib/step-ssh/ssh_host_ed25519_key-cert.pub";
  hostKey = "/etc/ssh/ssh_host_ed25519_key";
in {
  den.aspects.ssh-host-cert-renew.nixos = {
    host,
    pkgs,
    lib,
    ...
  }: let
    renewScript = pkgs.writeShellApplication {
      name = "ssh-host-cert-renew";
      runtimeInputs = [pkgs.step-cli pkgs.systemd];
      text = ''
        step ssh renew --force \
          --ca-url ${caUrl} --root /etc/step/ca-root.crt \
          --out ${liveCert} ${liveCert} ${hostKey}
        # Pick up the new cert without dropping live connections.
        systemctl try-reload-or-restart sshd.service
      '';
    };

    # Deploy the machinery wherever the host is SSH-enabled and the CA anchor is
    # in the flake. The renewer itself stays dormant (see ConditionPathExists)
    # until the host is enrolled and a live cert exists.
    active = host.ssh.enable && hasRootAnchor;
  in
    lib.mkIf active {
      environment.systemPackages = [pkgs.step-cli];

      # CA root, so `step` can verify the CA's HTTPS endpoint (public material).
      environment.etc."step/ca-root.crt".text = builtins.readFile rootAnchor;

      systemd.tmpfiles.rules = ["d /var/lib/step-ssh 0755 root root - -"];

      # This aspect owns the served host cert. sshd tolerates the file being
      # absent (falls back to the raw host key), so an un-enrolled host still
      # boots and is reachable via authorized_keys until enrolled.
      services.openssh.settings.HostCertificate = lib.mkForce liveCert;

      systemd.services.ssh-host-cert-renew = {
        description = "Renew this host's SSH host certificate via step-ca (SSHPOP)";
        after = ["network-online.target" "sshd.service"];
        wants = ["network-online.target"];
        # Dormant (not failed) until the host is enrolled and a cert exists;
        # the enroll step drops the cert and restarts this unit.
        unitConfig.ConditionPathExists = liveCert;
        serviceConfig = {
          Type = "oneshot";
          ExecStart = lib.getExe renewScript;
        };
      };

      systemd.timers.ssh-host-cert-renew = {
        description = "Daily SSH host-cert renewal";
        wantedBy = ["timers.target"];
        timerConfig = {
          OnCalendar = "daily";
          Persistent = true;
          RandomizedDelaySec = "1h";
        };
      };
    };
}
