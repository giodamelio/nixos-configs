{ inputs, ... }@flakeContext:
{ config, lib, pkgs, ... }: {
  config = {
    environment = {
      systemPackages = [
        pkgs.curl
        pkgs.xh
        pkgs.ripgrep
        pkgs.fd
        pkgs.wget
        pkgs.nnn
        pkgs.neovim
      ];
    };
    programs = {
      neovim = {
        defaultEditor = true;
        enable = true;
      };
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
    };
    users = {
      users = {
        server = {
          extraGroups = [
            "wheel"
          ];
          isNormalUser = true;
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
