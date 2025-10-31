# My Nix and NixOS configs

Used to configure all of my machines

# Machines

There are currently 7 machines listed in the [data](./homelab.toml)


  - `cadmium`
    - Description: Main development machine
    - Hardware: Desktop machine under my desk
  - `calcium`
    - Description: Hacking random projects while on Windows
    - Hardware: WSL2 Distro on Cadmium's Windows 11 install
  - `carbon`
    - Description: LAN VPN and other important services
    - Hardware: HP EliteDesk Mini Computer
  - `cesium`
    - Description: Super portable travel machine
    - Hardware: Cheap Lenovo Chromebook
  - `gallium`
    - Description: NAS running TruNAS Scale. Also runs storage based servers (Garage for S3, Syncthing)
    - Hardware: QNAP TS-462-2G
  - `gio-pixel-7`
    - Description: My Phone
    - Hardware: Pixel 7 Pro
  - `manganese`
    - Description: Handling all our monitoring as reliably as possible
    - Hardware: 

# Neovim AppImages

Github Actions builds a static Neovim AppImage with my config baked in:

    $ curl -LO https://f001.backblazeb2.com/file/gio-neovim-appimages/nvim.AppImage
    $ chmod +x nvim.AppImage
    $ ./nvim.AppImage

# The great delete

[Here](https://github.com/giodamelio/nixos-configs/tree/before-great-delete) is the repo before the great delete.
