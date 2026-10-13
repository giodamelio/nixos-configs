# Deploy nixosConfigurations.aluminum into the chroot on the phone. There is no
# systemd there, so this replaces switch-to-configuration: copy the closure, set
# the system profile, then let the new system's aluminum-start run NixOS
# activation and restart sshd + nix-daemon.
#   aluminum-deploy root@<phone-ip>
#   aluminum-deploy root@<phone-ip> --builders 'ssh-ng://… aarch64-linux …' --max-jobs 0
def --wrapped main [target: string, ...nix_args: string] {
  let attr = ".#nixosConfigurations.aluminum.config.system.build.toplevel"
  let system = (nix build --no-link --print-out-paths $attr ...$nix_args | str trim)
  print $"built ($system)"

  # sshd's default PATH has no nix-daemon on the bootstrap. remote-store=local:
  # the deployed system defaults Nix to the daemon socket, and the daemon may not
  # be running. Builds from our own builders are unsigned; root is a trusted user
  # there, as for nixos-rebuild.
  nix copy --no-check-sigs --to $"ssh-ng://($target)?remote-program=/sw/bin/nix-daemon&remote-store=local" $system

  # Absolute paths: the bootstrap env is always there and on a GC root, while
  # the deployed system's PATH only exists after activation. NIX_REMOTE: the
  # running generation's login env may point Nix at a daemon that is not up.
  ssh $target $"export NIX_REMOTE=auto && /sw/bin/nix-env -p /nix/var/nix/profiles/system --set ($system) && ($system)/sw/bin/aluminum-start --restart"
  print $"aluminum is now running ($system)"
}
