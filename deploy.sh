#!/usr/bin/env bash

# Check for the correct number of arguments
if [ "$#" -ne 2 ]; then
    echo "Usage: $0 <hostname> <ssh_user@ip>"
    exit 1
fi

# Assign input arguments to variables
HOSTNAME=$1
SSH_DESTINATION=$2

# Build the system configuration
nix build .#nixosConfigurations."$HOSTNAME".config.system.build.toplevel

# Extract the store path from the result
STORE_PATH=$(readlink -f ./result)

# Copy the built system to the target machine
nix copy --substitute-on-destination --to ssh://"$SSH_DESTINATION" "$STORE_PATH"

# Switch to the new config
ssh "$SSH_DESTINATION" "sudo $STORE_PATH/bin/switch-to-configuration switch"

# Set the nix profile to the new system
ssh "$SSH_DESTINATION" "sudo nix-env --profile /nix/var/nix/profiles/system --set $STORE_PATH"

# I need this to get a new systemd-boot entry, I didn't think I would need this though
ssh "$SSH_DESTINATION" "sudo /run/current-system/bin/switch-to-configuration boot"

