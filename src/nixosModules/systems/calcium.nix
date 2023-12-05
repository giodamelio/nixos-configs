{root, ...}: {
  config,
  lib,
  pkgs,
  ...
}: {
  imports = [
    # Setup the bootloader to handle zfs
    root.nixosModules.core-bootloader-zfs
  ];

  config = {
    networking.hostName = "calcium";
    nix = {
      settings = {
        experimental-features = ["nix-command" "flakes"];
        trusted-users = ["root" "@wheel"];
      };
    };
    programs = {
      direnv = {
        enable = true;
      };
      zsh = {
        enable = true;
      };
    };
    security = {
      sudo = {
        wheelNeedsPassword = false;
      };
    };
    users = {
      users = {
        giodamelio = {
          extraGroups = [
            "wheel"
          ];
          isNormalUser = true;
          shell = pkgs.zsh;
          openssh = {
            authorizedKeys = {
              keys = [
                "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKaKx5hPY3/SHy+xezxd5IsCmDoFTMIbqxTonmVVC0GB giodamelio@DESKTOP-LP2IMU5"
                "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAZF+j6HGldFqQdp+CaPaYKGMsFpUsk49jqhb7VtdUvn giodamelio@cadmium"
                "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFbUQ/gUuzZbOtBPseVWL1GVrjP08JqdNwHdndQgH+Am giodamelio@penguin"
              ];
            };
          };
        };
      };
    };
  };
}
