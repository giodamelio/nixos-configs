{flake, ...}: {
  imports = [
    flake.nixosModules.niri
  ];

  # Cadmium uses programs.ssh.startAgent, which conflicts with
  # gcr-ssh-agent enabled by the niri-flake NixOS module.
  services.gnome.gcr-ssh-agent.enable = false;
}
