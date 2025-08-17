#!/usr/bin/env nix-shell
#!nix-shell -i bash -p nix-output-monitor

#shellcheck disable=SC2029,SC1008
# Exit on any error
set -e

# Check for the correct number of arguments
if [ "$#" -ne 2 ]; then
    echo "Usage: $0 <hostname> <ssh_user@ip>"
    exit 1
fi

# Assign input arguments to variables
HOSTNAME=$1
SSH_DESTINATION=$2

# Use NH to build and deploy
nh os switch --hostname "$HOSTNAME" --target-host "$SSH_DESTINATION" .

