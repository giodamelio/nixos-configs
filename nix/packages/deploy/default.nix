{
  pkgs,
  lib,
  ...
}: hostname: ssh_destination:
pkgs.writeShellApplication {
  name = "deploy-${hostname}";
  runtimeInputs = [];
  text = ''
    # Build the system configuration
    nix build .#nixosConfigurations."${hostname}".config.system.build.toplevel

    # Extract the store path from the result
    STORE_PATH=$(readlink -f ./result)

    # Copy the built system to the target machine
    nix copy --substitute-on-destination --to ssh://"${ssh_destination}" "$STORE_PATH"

    # Switch to the new config
    ssh "${ssh_destination}" "sudo $STORE_PATH/bin/switch-to-configuration switch"

    # Set the nix profile to the new system
    ssh "${ssh_destination}" "sudo nix-env --profile /nix/var/nix/profiles/system --set $STORE_PATH"

    # I need this to get a new systemd-boot entry, I didn't think I would need this though
    ssh "${ssh_destination}" "sudo /run/current-system/bin/switch-to-configuration boot"
  '';
}
