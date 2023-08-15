{...}: {
  config,
  lib,
  pkgs,
  ...
}: {
  config = {
    networking.hostName = "beryllium";
    environment = {
      etc."issue.d/ip.issue".text = "\\4{eth0}\n";
    };
    nix = {
      settings = {
        experimental-features = ["nix-command" "flakes"];
        trusted-users = ["root" "@wheel"];
      };
    };
    programs = {
      neovim = {
        enable = true;
        defaultEditor = true;
        viAlias = true;
        vimAlias = true;
      };
      zsh.enable = true;
    };
    security = {
      sudo = {
        wheelNeedsPassword = false;
      };
    };
    services = {
      openssh = {
        enable = true;
      };
      tailscale = {
        enable = true;
      };
    };
    users = {
      users = {
        server = {
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
    age = {
      secrets = {
        test_secret.file = ../../../secrets/test_secret.age;
      };
    };
  };
}
