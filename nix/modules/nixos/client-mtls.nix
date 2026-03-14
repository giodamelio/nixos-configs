{pkgs, ...}: {
  # Client mTLS certificate renewal module
  #
  # Initial enrollment is manual and requires:
  # 1. Copy root CA from server: scp carbon:/var/lib/step-ca/certs/root_ca.crt /var/lib/mtls-client/
  # 2. Get CA fingerprint: step certificate fingerprint /var/lib/mtls-client/root_ca.crt
  # 3. Request certificate: step ca certificate "client-hostname" /var/lib/mtls-client/client.crt /var/lib/mtls-client/client.key \
  #      --ca-url https://ca.gio.ninja:8443 --root /var/lib/mtls-client/root_ca.crt --provisioner admin
  # 4. Enter provisioner password when prompted (from step-ca-init bootstrap)

  environment.systemPackages = [pkgs.step-cli];

  systemd.services.mtls-client-renew = {
    description = "Renew mTLS client certificate";
    serviceConfig = {
      Type = "oneshot";
      StateDirectory = "mtls-client";
      StateDirectoryMode = "0700";
      ExecStart = "${pkgs.step-cli}/bin/step ca renew /var/lib/mtls-client/client.crt /var/lib/mtls-client/client.key --ca-url https://ca.gio.ninja:8443 --root /var/lib/mtls-client/root_ca.crt --force";
    };
  };

  systemd.timers.mtls-client-renew = {
    wantedBy = ["timers.target"];
    timerConfig = {
      OnCalendar = "daily";
      RandomizedDelaySec = "1h";
      Persistent = true;
    };
  };
}
