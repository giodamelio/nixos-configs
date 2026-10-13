# My Nix and NixOS configs

Used to configure all of my machines

# Machines

There are currently 11 machines listed in the [data](./homelab.toml)


  - `aluminum`
    - Description: Native ARM (aarch64) remote builder
    - Hardware: Google Pixel 7 (Tensor G2, 8 GB), rooted, NixOS in a chroot under Android
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
  - `hammond`
    - Description: Hammond AI agent
    - Hardware: Intel NUC 5th Gen
  - `oganesson`
    - Description: Native ARM (aarch64) remote builder
    - Hardware: Oracle Cloud Always Free Ampere A1 VM (2 OCPU, 12 GB, aarch64)
  - `rhodium`
    - Description: Critical infrastructure DNS server
    - Hardware: Raspberry Pi 4
  - `strontium`
    - Description: Certificate authority and secret manager
    - Hardware: Raspberry Pi 3B+

# IP Ranges

| Name    | CIDR            | VLAN Tag | Description                                                            |
|---------|-----------------|----------|------------------------------------------------------------------------|
| Trusted | `10.0.0.1/16`   | 1        | Trusted family devices, can route to everything on the LAN             |
| Public  | `10.20.0.1/16`  | 2        | For guests and untrusted devices, can only route to each other and WAN |
| Homelab | `10.30.0.1/16`  | 3        | Homelab servers                                                        |
| VPN     | `10.100.0.1/22` |          | VPN for trusted devices, can route to everything on the LAN            |

# Wifi Networks

| SSID      | VLAN Tag | Description               |
|-----------|----------|---------------------------|
| Interwebs | 2        | Attached to guest network |
| SGD       | 1        | Trusted family devices    |

# Neovim AppImages

Github Actions builds a static Neovim AppImage with my config baked in:

    $ curl -LO https://f001.backblazeb2.com/file/gio-neovim-appimages/nvim.AppImage
    $ chmod +x nvim.AppImage
    $ ./nvim.AppImage

# The great delete

[Here](https://github.com/giodamelio/nixos-configs/tree/before-great-delete) is the repo before the great delete.
