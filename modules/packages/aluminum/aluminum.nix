# aluminum: a den host (modules/hosts/aluminum) that lives in a chroot on a
# rooted Android phone (docs/aluminum.md). Two packages:
# - aluminum-bootstrap: the first-install tarball. A Nix store, nix-daemon and
#   root SSH, just enough to receive the real system. Only the tarball step runs
#   on the build machine; the contents are aarch64 store paths fetched from the
#   binary cache, so it compiles nothing and needs no qemu.
# - aluminum-deploy: builds nixosConfigurations.aluminum, copies it over and
#   activates it inside the chroot (there is no systemd, so no switch-to-configuration).
{inputs, ...}: let
  homelab = builtins.fromTOML (builtins.readFile ../../../homelab.toml);
in {
  perSystem = {pkgs, ...}: let
    inherit (pkgs) lib;
    aarch64 = inputs.nixpkgs.legacyPackages.aarch64-linux;

    # The host's buildEnv: it only creates symlinks, so linking aarch64 paths
    # from an x86 builder is fine and keeps every build step native.
    env = pkgs.buildEnv {
      name = "aluminum-bootstrap-env";
      paths = with aarch64; [
        nix
        openssh
        bashInteractive
        coreutils
        findutils
        gnugrep
        gnused
        gnutar
        gzip
        xz
        procps
        util-linux
        iproute2
        cacert
      ];
    };

    # Runs on Android (toybox sh), outside the chroot. NixOS activation expects a
    # fresh /run each boot, as on a real machine.
    up = ''
      #!/system/bin/sh
      R=''${R:-/data/local/aluminum}
      # Android's SELinux policy blocks a foreign userland from running.
      setenforce 0
      for d in dev dev/pts proc sys; do
        mountpoint -q "$R/$d" || mount --bind "/$d" "$R/$d"
      done
      mountpoint -q "$R/run" || mount -t tmpfs -o mode=0755 tmpfs "$R/run"
      chroot "$R" /sw/bin/bash /aluminum/inside-start "$@"
    '';

    # Runs inside the chroot as root. Once a system is deployed, its own
    # aluminum-start takes over, so this script only ever needs to receive one.
    insideStart = ''
      #!/sw/bin/bash
      set -euo pipefail
      export PATH=/sw/bin

      if [ ! -e /nix/var/nix/.loaded ]; then
        nix-store --load-db < /nix-path-registration
        touch /nix/var/nix/.loaded
      fi

      start=/nix/var/nix/profiles/system/sw/bin/aluminum-start
      if [ -x "$start" ]; then
        exec "$start" "$@"
      fi

      [ -e /etc/ssh/ssh_host_ed25519_key ] ||
        ssh-keygen -q -t ed25519 -N "" -f /etc/ssh/ssh_host_ed25519_key
      if ! pgrep -f 'nix-daemon --daemon' >/dev/null; then
        setsid --fork nix-daemon --daemon </dev/null >/dev/null 2>&1
      fi
      if ! { [ -e /run/sshd.pid ] && kill -0 "$(cat /run/sshd.pid)" 2>/dev/null; }; then
        sshd -f /etc/ssh/sshd_config
      fi
    '';

    etc = {
      passwd = ''
        root:x:0:0:root:/root:/sw/bin/bash
        sshd:x:74:74:sshd privilege separation:/var/empty:/sw/bin/false
      '';
      group = ''
        root:x:0:
        sshd:x:74:
      '';
      # root `*`, not `!`: without PAM, sshd treats `!` as a locked account and
      # refuses even key logins.
      shadow = ''
        root:*:1::::::
        sshd:!:1::::::
      '';
      "nsswitch.conf" = ''
        passwd: files
        group: files
        shadow: files
        hosts: files dns
      '';
      hostname = ''
        aluminum
      '';
      hosts = ''
        127.0.0.1 localhost aluminum
        ::1 localhost aluminum
      '';
      "resolv.conf" = ''
        nameserver 10.30.0.11
        nameserver 1.1.1.1
      '';
      # Root owns the store and runs the builds until the deployed system brings
      # build users; Android's kernel may lack the namespaces the sandbox needs.
      "nix/nix.conf" = ''
        experimental-features = nix-command flakes
        build-users-group =
        sandbox = false
        trusted-users = root
      '';
      # Port 22: nothing on Android listens there.
      "ssh/sshd_config" = ''
        Port 22
        HostKey /etc/ssh/ssh_host_ed25519_key
        PidFile /run/sshd.pid
        PermitRootLogin prohibit-password
        AllowUsers root
        PasswordAuthentication no
        KbdInteractiveAuthentication no
        AuthorizedKeysFile /etc/ssh/authorized_keys/%u
      '';
      "ssh/authorized_keys/root" = lib.concatMapStrings (key: "${key}\n") homelab.ssh_keys;
    };

    contents =
      lib.mapAttrsToList (path: text: {
        source = pkgs.writeText (lib.replaceStrings ["/"] ["-"] path) text;
        target = "/etc/${path}";
      })
      etc
      ++ [
        {
          source = pkgs.writeText "aluminum-up" up;
          target = "/aluminum/up";
        }
        {
          source = pkgs.writeText "aluminum-inside-start" insideStart;
          target = "/aluminum/inside-start";
        }
      ];

    bootstrap = pkgs.callPackage "${pkgs.path}/nixos/lib/make-system-tarball.nix" {
      fileName = "aluminum-bootstrap";
      inherit contents;
      storeContents = [
        {
          object = env;
          symlink = "/sw";
        }
      ];
      # Android's toybox tar unpacks gzip natively; it has no xz.
      compressCommand = "gzip -6";
      compressionExtension = ".gz";
      extraInputs = [pkgs.gzip];
      # make-system-tarball runs this unquoted, so it must be one command line.
      extraCommands = lib.getExe (pkgs.writeShellApplication {
        name = "aluminum-bootstrap-layout";
        text = ''
          chmod 0600 etc/shadow
          chmod 0755 aluminum/up aluminum/inside-start
          # Real directories, not symlinks into the store: NixOS activation
          # writes /bin/sh and /usr/bin/env into them.
          mkdir -p bin usr/bin
          ln -s /sw/bin/bash bin/bash
          ln -s /sw/bin/bash bin/sh
          ln -s /sw/bin/env usr/bin/env
          mkdir -p etc/ssl/certs
          ln -s /sw/etc/ssl/certs/ca-bundle.crt etc/ssl/certs/ca-certificates.crt
          # Keep the bootstrap env (and its scripts' interpreter) across GC once a
          # deployed system exists.
          mkdir -p nix/var/nix/gcroots
          ln -s /sw nix/var/nix/gcroots/aluminum-bootstrap
          mkdir -p dev proc sys run root var/empty
          mkdir -m 1777 tmp
        '';
      });
    };

    deploy = inputs.self.lib.writeNushellApplication pkgs {
      name = "aluminum-deploy";
      runtimeInputs = [pkgs.openssh pkgs.nix];
      source = builtins.readFile ./aluminum-deploy.nu;
      meta.mainProgram = "aluminum-deploy";
    };
  in {
    packages = {
      aluminum-bootstrap = bootstrap;
      aluminum-deploy = deploy;
    };
  };
}
