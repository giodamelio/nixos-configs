# My Nix and NixOS configs

[![built with garnix](https://img.shields.io/endpoint.svg?url=https%3A%2F%2Fgarnix.io%2Fapi%2Fbadges%2Fgiodamelio%2Fnixos-configs%3Fbranch%3Dmain)](https://garnix.io/repo/giodamelio/nixos-configs)

Used to configure all of my machines

# Machines

There are currently 7 machines listed in the [data](./homelab.toml)


  - `cadmium`
    - Description: Main development machine
    - Hardware: Desktop machine under my desk
  - `calcium`
    - Description: Hacking random projects while on Windows
    - Hardware: WSL2 Distro on Cadmium's Windows 11 install
  - `cesium`
    - Description: Super portable travel machine
    - Hardware: Cheap Lenovo Chromebook
  - `gallium`
    - Description: NAS. Also runs storage based servers (Garage for S3, Syncthing)
    - Hardware: QNAP TS-462-2G
  - `gio-pixel-7`
    - Description: My Phone
    - Hardware: Pixel 7 Pro
  - `lithium1`
    - Description: Headscale Gateway. Also other networking things that need always online with a public IP
    - Hardware: A Vulture VPS
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
