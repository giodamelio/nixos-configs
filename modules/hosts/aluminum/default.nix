# aluminum — a spare, rooted Pixel 7 (Tensor G2, 8 cores, 8 GB) running this
# NixOS system in a chroot under Android, as a native aarch64 remote builder.
# Android's init stays PID 1, so nothing here runs as a systemd service:
# aluminum-start (below) runs activation and starts sshd + nix-daemon itself,
# and aluminum-deploy replaces switch-to-configuration. See docs/aluminum.md.
{lib, ...}: let
  homelab = builtins.fromTOML (builtins.readFile ../../../homelab.toml);
in {
  den.hosts.aarch64-linux.aluminum = {
    role = "server";
    # Generated on the phone at first bootstrap
    # (/data/local/aluminum/etc/ssh/ssh_host_ed25519_key.pub); remote-builder-user
    # pins it.
    ssh.hostKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBkwatvEfeFia/FlR11UrIU0Uw/SybRDLspLN4tx4n98";
    users.server.classes = [];
    # Android owns the network; the chroot only shares it.
    network.mode = "unmanaged";
    remoteBuilder = {
      enable = true;
      hostName = "aluminum.gio.ninja";
      systems = ["aarch64-linux"];
      maxJobs = 4;
      supportedFeatures = ["big-parallel"];
    };
  };

  den.aspects.aluminum.nixos = {
    config,
    host,
    pkgs,
    ...
  }: let
    buildUsers = map (n: "nixbld${toString n}") (lib.range 1 config.nix.nrBuildUsers);

    # The fleet heartbeat (Telegraf) assumes systemd; this sends the same
    # Healthchecks pings (FAIL lines first, URL/fail when any check fails) from
    # the signals that matter on a phone.
    aluminumHeartbeat = pkgs.writeShellApplication {
      name = "aluminum-heartbeat";
      runtimeInputs = [pkgs.coreutils pkgs.procps pkgs.iputils pkgs.curl];
      text = ''
        url=$(cat /var/lib/aluminum/healthcheck_url)
        battery=/sys/class/power_supply/battery

        probe() {
          local name=$1
          shift
          if "$@" >/dev/null 2>&1; then ok+=("$name"); else fail+=("$name"); fi
        }

        while true; do
          ok=()
          fail=()

          used=$(df --output=pcent / | tail -n 1 | tr -dc 0-9)
          probe disk:/ test "$used" -lt 90
          probe battery:capacity test "$(cat "$battery/capacity")" -ge 50
          probe battery:temp test "$(($(cat "$battery/temp") / 10))" -le 50
          probe battery:health test "$(cat "$battery/health")" = Good
          probe daemon:nix-daemon pgrep -x nix-daemon
          probe daemon:sshd pgrep -x sshd
          probe internet ping -c 3 -W 2 1.1.1.1

          message=""
          for name in $(printf '%s\n' "''${fail[@]}" | sort); do message+="FAIL $name"$'\n'; done
          for name in $(printf '%s\n' "''${ok[@]}" | sort); do message+="OK   $name"$'\n'; done
          target=$url
          if [ "''${#fail[@]}" -gt 0 ]; then target="$url/fail"; fi

          curl -fsS -m 10 --retry 3 -o /dev/null --data-binary "$message" "$target" ||
            echo "aluminum-heartbeat: ping to Healthchecks failed" >&2
          sleep 240
        done
      '';
    };

    # What systemd would do at boot and on switch. The bootstrap's inside-start
    # hands over to this once a system is deployed, so changes ship with a deploy.
    aluminumStart = pkgs.writeShellApplication {
      name = "aluminum-start";
      runtimeInputs = [pkgs.coreutils pkgs.util-linux pkgs.procps pkgs.openssh config.nix.package];
      text = ''
        # The security wrappers can't run from Android's tmpfs (no xattrs), and
        # /data is nosuid; a suid bind mount of a /data dir gives them both.
        mkdir -p /var/lib/aluminum/wrappers /run/wrappers
        if ! mountpoint -q /run/wrappers; then
          mount --bind /var/lib/aluminum/wrappers /run/wrappers
          mount -o remount,bind,suid /run/wrappers
        fi

        # Snippets that expect systemd can fail in a chroot; sshd must still
        # come up afterwards, or the only way back in is adb.
        /nix/var/nix/profiles/system/activate || echo "aluminum: activation reported errors" >&2

        [ -e /etc/ssh/ssh_host_ed25519_key ] ||
          ssh-keygen -q -t ed25519 -N "" -f /etc/ssh/ssh_host_ed25519_key

        if [ "''${1:-}" = --restart ]; then
          if [ -e /run/sshd.pid ]; then kill "$(cat /run/sshd.pid)" 2>/dev/null || true; fi
          pkill -f 'nix-daemon --daemon' || true
          pkill -f aluminum-heartbeat || true
          sleep 1
        fi

        # No syslog in the chroot, so these log to files.
        mkdir -p /var/log/aluminum
        # --fork rather than `&`: a background subshell would keep the caller's
        # stdout open, and an ssh deploy would never see EOF.
        if ! pgrep -f 'nix-daemon --daemon' >/dev/null; then
          setsid --fork nix-daemon --daemon </dev/null >>/var/log/aluminum/nix-daemon.log 2>&1
        fi
        if ! { [ -e /run/sshd.pid ] && kill -0 "$(cat /run/sshd.pid)" 2>/dev/null; }; then
          ${config.services.openssh.package}/bin/sshd -f /etc/ssh/sshd_config -E /var/log/aluminum/sshd.log
        fi
        if ! pgrep -f aluminum-heartbeat >/dev/null; then
          setsid --fork ${lib.getExe aluminumHeartbeat} </dev/null >>/var/log/aluminum/heartbeat.log 2>&1
        fi
      '';
    };
  in {
    environment.systemPackages = [aluminumStart];

    networking.hostName = "aluminum";

    # No kernel, initrd or bootloader: Android boots the phone.
    boot.isContainer = true;
    # isContainer assumes the host's nix-daemon; this chroot runs its own, and
    # root must reach the store directly (as on any NixOS host) when it is down.
    environment.variables.NIX_REMOTE = lib.mkForce "auto";
    # Setuid wrappers (sudo, ...) come from a systemd oneshot that never runs
    # here; aluminum-start gives /run/wrappers a suid mount first.
    system.activationScripts.wrappers = {
      deps = ["specialfs" "users"];
      text = ''
        mkdir -p /run/wrappers
        ${config.systemd.services.suid-sgid-wrappers.serviceConfig.ExecStart}
      '';
    };
    # Android owns netfilter and DHCP; the firewall service would never run here.
    networking.firewall.enable = false;
    networking.useDHCP = false;

    # Android's kernel may lack the namespaces the build sandbox needs.
    nix.settings.sandbox = false;

    # Android's "paranoid networking" only lets members of aid_inet (3003) and
    # aid_net_raw (3004) open sockets. Builds that fetch run as nixbld users.
    users.groups = {
      aid_inet = {
        gid = 3003;
        members = buildUsers;
      };
      aid_net_raw = {
        gid = 3004;
        members = buildUsers;
      };
    };

    # Android gives low uids (1000 = system, 2000 = shell, ...) special powers in
    # the kernel; keep chroot accounts in the OEM-reserved range instead.
    # Immutable: the bootstrap seeds /etc/shadow, and mutable users would keep
    # its entries over the config's.
    users.mutableUsers = false;
    users.users =
      {
        server.uid = 5001;
        # aluminum-deploy works as root, as it must on the bootstrap.
        root.openssh.authorizedKeys.keys = homelab.ssh_keys;
      }
      // lib.optionalAttrs host.remoteBuilder.enable {
        nix-remote-builder.uid = 5000;
      };

    services.openssh = {
      enable = true;
      ports = [22];
      hostKeys = [
        {
          type = "ed25519";
          path = "/etc/ssh/ssh_host_ed25519_key";
        }
      ];
      settings = {
        # basic-settings forbids root login fleet-wide; see root above.
        PermitRootLogin = lib.mkForce "prohibit-password";
      };
    };

    documentation.enable = false;
    system.stateVersion = "26.11";
  };
}
