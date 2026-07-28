# strontium — Raspberry Pi 3B+ SD-image host: CA + secret manager
# (docs/pi-ca-secrets-plan.md). Base scaffold only; step-ca lands later.
{den, ...}: {
  # Same shape as rhodium: role=server attaches the shared `server` user aspect,
  # base bundle arrives via den.default.
  den.hosts.aarch64-linux.strontium = {
    role = "server";
    ssh = {
      enable = true;
      hostKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHgIZEMTZZT4Wldwboskghc3aaGbA8BB5gs86hLh+ppR";
    };
    users.server.classes = [];

    # Static networking rendered by the network aspect (see gallium).
    network = {
      mode = "static";
      # USB lan78xx NIC — path-based predictable name, confirmed on hardware
      interfaces.enu1u1u1 = {
        address = "10.30.0.13";
        prefixLength = 24;
        gateway = "10.30.0.1";
      };
    };
  };

  # Run the heartbeat collector (pushes to its own Healthchecks check).
  den.aspects.strontium.includes = [
    den.aspects.server-heartbeat
    den.aspects.rayfish
  ];

  den.aspects.strontium.nixos = {
    modulesPath,
    pkgs,
    lib,
    ...
  }: {
    # agevault delivers these (asserted against secrets.toml at eval time).
    fleet.credentials.needs = [
      "restic_password"
      "restic_s3_credentials"
    ];

    imports = [
      # sd-image-aarch64 (not raw sd-image) populates the firmware partition
      # (start.elf, config.txt, u-boot-rpi3) and extlinux — raw sd-image.nix
      # yields an unbootable image (see rhodium bring-up).
      "${modulesPath}/installer/sd-card/sd-image-aarch64.nix"

      {
        networking.hostName = "strontium";
        sdImage.compressImage = false;
        console.enable = true;
        # Mainline kernel: GPIO-header mini UART is ttyS1. bcm2837 peripherals
        # sit at 0x3f00_0000 (Pi 4 was 0xfe00_0000). mkAfter so our console=
        # lands last (= /dev/console, stage-1 shell on serial).
        boot.kernelParams = lib.mkAfter [
          "earlycon=uart8250,mmio32,0x3f215040"
          "keep_bootcon"
          "loglevel=7"
          "console=ttyS1,115200n8"
        ];
        # Headless, ethernet-only — no Bluetooth, no WiFi. All front-ends must
        # be listed or they'd pull core modules in as dependencies despite the
        # blacklist.
        boot.blacklistedKernelModules = [
          "hci_uart"
          "btbcm"
          "btsdio"
          "bluetooth"
          "brcmfmac"
          "brcmutil"
        ];
        # TEMPORARY: serial-console autologin for bring-up debugging; remove once deployed
        services.getty.autologinUser = "server";
        hardware.enableRedistributableFirmware = lib.mkDefault true;
        # No ZFS on this host (SD-only per the plan)
        boot.supportedFilesystems.zfs = lib.mkForce false;
        boot.initrd.allowMissingModules = true;

        # 1 GB RAM + minimize SD writes (locked in docs/pi-ca-secrets-plan.md)
        zramSwap.enable = true;
        services.journald.extraConfig = ''
          SystemMaxUse=64M
          RuntimeMaxUse=64M
        '';
      }

      # Interface/addressing comes from the network aspect (host.network above)
      {
        networking = {
          firewall = {
            enable = true;
            allowPing = true;
          };
          nftables.enable = true;
        };
      }

      # Raspberry Pi utilities (no raspberrypi-eeprom: Pi 3 has no SPI EEPROM)
      {
        environment.systemPackages = with pkgs; [
          libraspberrypi
          restic # manual snapshot inspection (see docs/pi-ca-secrets-plan.md)
        ];
      }

      # Backup important files to Garage on Gallium
      ({pkgs, ...}: let
        # Report the backup result to the fleet monitor. Its own unit (triggered by
        # OnSuccess=/OnFailure= below) so the credential loads cleanly and the
        # outcome comes from $MONITOR_SERVICE_RESULT — no postStop credential hack.
        resticPing = pkgs.writeShellApplication {
          name = "restic-backup-ping";
          runtimeInputs = [pkgs.curl];
          text = ''
            if [ "''${MONITOR_SERVICE_RESULT:-}" = "success" ]; then s=true; else s=false; fi
            curl -fsS -m 10 -X POST \
              -H "Authorization: Bearer $(cat "$CREDENTIALS_DIRECTORY/gatus_push_token")" \
              "http://rhodium.gio.ninja:8080/api/v1/endpoints/backups_strontium-restic/external?success=$s" || true
          '';
        };
      in {
        services.restic.backups.strontium = {
          repository = "s3:https://s3.garage.gio.ninja/strontium-backups";
          # The auto wrapper doesn't load the systemd credential correctly, so we create one ourselves below
          createWrapper = false;
          passwordFile = "/run/credentials/restic-backups-strontium.service/restic_password";
          paths = ["/var/lib/gio-ca" "/var/lib/step-ca"];
          initialize = true;
          timerConfig.OnCalendar = "daily";
          pruneOpts = ["--keep-daily 7" "--keep-weekly 4" "--keep-monthly 6"];
        };

        systemd.services.restic-backups-strontium = {
          serviceConfig.LoadCredentialEncrypted = [
            "restic_password"
            "restic_s3_credentials"
          ];
          # Fire the ping on both outcomes; it reads which via $MONITOR_SERVICE_RESULT.
          unitConfig = {
            OnSuccess = "restic-backup-ping.service";
            OnFailure = "restic-backup-ping.service";
          };
          environment = {
            AWS_DEFAULT_REGION = "garage";
            AWS_SHARED_CREDENTIALS_FILE = "/run/credentials/restic-backups-strontium.service/restic_s3_credentials";
          };
        };

        # gatus_push_token (symlinked from rhodium) authenticates the ping.
        fleet.credentials.needs = ["gatus_push_token"];

        systemd.services.restic-backup-ping = {
          description = "Report the restic backup result to the fleet monitor";
          serviceConfig = {
            Type = "oneshot";
            LoadCredentialEncrypted = ["gatus_push_token"];
            ExecStart = "${resticPing}/bin/restic-backup-ping";
          };
        };

        # Interactive restic wrapper with credentials loaded
        # $ sudo restic-strontium snapshots
        environment.systemPackages = [
          (pkgs.writeShellScriptBin "restic-strontium" ''
            exec ${pkgs.systemd}/bin/systemd-run --pipe --collect --quiet --unit=restic-strontium-cli \
              -p LoadCredentialEncrypted=restic_password \
              -p LoadCredentialEncrypted=restic_s3_credentials \
              -E RESTIC_REPOSITORY=s3:https://s3.garage.gio.ninja/strontium-backups \
              -E AWS_DEFAULT_REGION=garage \
              -E RESTIC_PASSWORD_FILE=/run/credentials/restic-strontium-cli.service/restic_password \
              -E AWS_SHARED_CREDENTIALS_FILE=/run/credentials/restic-strontium-cli.service/restic_s3_credentials \
              ${pkgs.restic}/bin/restic "$@"
          '')
        ];
      })
    ];

    nixpkgs.config.allowUnfree = true;
    system.stateVersion = "26.11";
  };
}
