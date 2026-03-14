{pkgs, ...}: {
  users.users.step-ca = {
    isSystemUser = true;
    group = "step-ca";
    home = "/var/lib/step-ca";
  };
  users.groups.step-ca = {};

  systemd.services.step-ca-init = {
    description = "Initialize step-ca Certificate Authority";
    before = ["step-ca.service"];
    requiredBy = ["step-ca.service"];
    unitConfig.ConditionPathExists = "!/var/lib/step-ca/config/ca.json";
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    path = [pkgs.step-cli pkgs.openssl pkgs.jq];
    script = ''
      set -euo pipefail

      export STEPPATH=$(mktemp -d)
      trap 'rm -rf "$STEPPATH"' EXIT

      openssl rand -base64 32 > "$STEPPATH/password"

      step ca init \
        --name "gio.ninja CA" \
        --dns ca.gio.ninja \
        --address :8443 \
        --provisioner admin \
        --password-file "$STEPPATH/password" \
        --provisioner-password-file "$STEPPATH/password" \
        --deployment-type standalone

      install -d -m 0750 -o step-ca -g step-ca /var/lib/step-ca/config
      install -d -m 0755 -o step-ca -g step-ca /var/lib/step-ca/certs
      install -d -m 0700 -o step-ca -g step-ca /var/lib/step-ca/db

      install -m 0644 -o step-ca -g step-ca "$STEPPATH/certs/root_ca.crt" /var/lib/step-ca/certs/
      install -m 0644 -o step-ca -g step-ca "$STEPPATH/certs/intermediate_ca.crt" /var/lib/step-ca/certs/

      # Create CA bundle for client cert verification (intermediate + root)
      cat "$STEPPATH/certs/intermediate_ca.crt" "$STEPPATH/certs/root_ca.crt" > /var/lib/step-ca/certs/ca-bundle.crt
      chown step-ca:step-ca /var/lib/step-ca/certs/ca-bundle.crt
      chmod 0644 /var/lib/step-ca/certs/ca-bundle.crt

      jq '
        .root = "/var/lib/step-ca/certs/root_ca.crt" |
        .crt = "/var/lib/step-ca/certs/intermediate_ca.crt" |
        .key = "/run/credentials/step-ca.service/intermediate_ca_key" |
        .db.dataSource = "/var/lib/step-ca/db" |
        .authority.provisioners[0].claims.maxTLSCertDuration = "8760h" |
        .authority.provisioners[0].claims.defaultTLSCertDuration = "720h"
      ' "$STEPPATH/config/ca.json" > /var/lib/step-ca/config/ca.json
      chown step-ca:step-ca /var/lib/step-ca/config/ca.json
      chmod 0640 /var/lib/step-ca/config/ca.json

      install -d -m 0700 /usr/lib/credstore.encrypted

      systemd-creds encrypt \
        --name=intermediate_ca_key \
        "$STEPPATH/secrets/intermediate_ca_key" \
        /usr/lib/credstore.encrypted/intermediate_ca_key

      systemd-creds encrypt \
        --name=ca-password \
        "$STEPPATH/password" \
        /usr/lib/credstore.encrypted/ca-password
    '';
  };

  systemd.services.step-ca = {
    description = "Smallstep CA Server";
    after = ["network-online.target"];
    wants = ["network-online.target"];
    wantedBy = ["multi-user.target"];
    serviceConfig = {
      ExecStart = "${pkgs.step-ca}/bin/step-ca /var/lib/step-ca/config/ca.json --password-file \${CREDENTIALS_DIRECTORY}/ca-password";
      User = "step-ca";
      Group = "step-ca";
      Type = "exec";
      StateDirectory = "step-ca";
      WorkingDirectory = "/var/lib/step-ca";
      Environment = "HOME=/var/lib/step-ca";
      ProtectSystem = "strict";
      ProtectHome = true;
      PrivateTmp = true;
      NoNewPrivileges = true;
      ReadWritePaths = ["/var/lib/step-ca/db"];
    };
  };

  # Template service for issuing client certificates
  # Usage: systemctl start mtls-issue@clientname.service
  # Certs stored in /var/lib/step-ca/client-certs/<clientname>/
  systemd.services."mtls-issue@" = {
    description = "Issue mTLS client certificate for %i";
    after = ["step-ca.service"];
    requires = ["step-ca.service"];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = false;
      Environment = "CLIENT=%i";
    };
    path = [pkgs.step-cli pkgs.openssl];
    script = ''
      set -euo pipefail
      CERT_DIR="/var/lib/step-ca/client-certs/$CLIENT"

      install -d -m 0755 -o step-ca -g step-ca /var/lib/step-ca/client-certs
      install -d -m 0700 -o step-ca -g step-ca "$CERT_DIR"

      step ca certificate "$CLIENT" \
        "$CERT_DIR/client.crt" \
        "$CERT_DIR/client.key" \
        --ca-url https://ca.gio.ninja:8443 \
        --root /var/lib/step-ca/certs/root_ca.crt \
        --provisioner admin \
        --provisioner-password-file "$CREDENTIALS_DIRECTORY/ca-password" \
        --not-after 8760h \
        --force

      cp /var/lib/step-ca/certs/root_ca.crt "$CERT_DIR/"
      cp /var/lib/step-ca/certs/intermediate_ca.crt "$CERT_DIR/"

      # Create CA chain for p12 bundle
      cat "$CERT_DIR/intermediate_ca.crt" "$CERT_DIR/root_ca.crt" > "$CERT_DIR/ca-chain.crt"

      # Generate PKCS12 bundle for browser import (includes full chain)
      openssl pkcs12 -export \
        -out "$CERT_DIR/client.p12" \
        -inkey "$CERT_DIR/client.key" \
        -in "$CERT_DIR/client.crt" \
        -certfile "$CERT_DIR/ca-chain.crt" \
        -name "$CLIENT mTLS" \
        -passout pass:

      chown -R step-ca:step-ca "$CERT_DIR"
      chmod 644 "$CERT_DIR/client.p12"

      echo "Certificate issued for $CLIENT"
      echo "Files: $CERT_DIR/{client.crt,client.key,client.p12,root_ca.crt}"
      echo "P12 has no password - import directly"
    '';
  };

  gio.credentials.services."mtls-issue@".loadCredentialEncrypted = [
    "ca-password"
  ];

  gio.credentials.services.step-ca.loadCredentialEncrypted = [
    "intermediate_ca_key"
    "ca-password"
  ];

  users.users.caddy.extraGroups = ["step-ca"];
  systemd.services.caddy.after = ["step-ca.service"];
  systemd.services.caddy.wants = ["step-ca.service"];
  services.gio.reverse-proxy.mtlsRootCaCertPath = "/var/lib/step-ca/certs/ca-bundle.crt";

  environment.systemPackages = [pkgs.step-cli];
  networking.firewall.allowedTCPPorts = [8443];
}
