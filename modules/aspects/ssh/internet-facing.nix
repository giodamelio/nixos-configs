# ssh-internet-facing — extra sshd hardening for hosts reachable from the whole
# internet, on top of the fleet baseline (no root, no passwords, modern
# algorithms). Key-only logins for the host's real accounts, nothing tunnelled
# through it, and fail2ban to cut off scanners early.
_: {
  den.aspects.ssh-internet-facing.nixos = {
    config,
    lib,
    ...
  }: {
    services.openssh.settings = {
      # The fleet leaves keyboard-interactive on; with it, PAM could still offer
      # a password prompt.
      KbdInteractiveAuthentication = false;
      AuthenticationMethods = "publickey";
      AllowUsers = lib.attrNames (lib.filterAttrs (_name: user: user.isNormalUser) config.users.users);

      LoginGraceTime = 20;
      # Start dropping unauthenticated connections at 10, all of them at 60.
      MaxStartups = "10:30:60";
      ClientAliveInterval = 300;
      ClientAliveCountMax = 2;

      # A foothold on the internet must not become a relay into the LAN.
      AllowTcpForwarding = false;
      AllowAgentForwarding = false;
      AllowStreamLocalForwarding = false;
      PermitTunnel = "no";
    };

    services.fail2ban = {
      enable = true;
      maxretry = 5;
      bantime = "1h";
      bantime-increment.enable = true;
      # Never lock out the LAN, its VPN clients or the rest of the VCN.
      ignoreIP = ["10.0.0.0/16" "10.30.0.0/24" "10.100.0.0/24" "10.250.0.0/16"];
      # Also count pre-auth probing (bad kex, no matching key type), not just
      # failed logins.
      jails.sshd.settings.mode = "aggressive";
    };
  };
}
