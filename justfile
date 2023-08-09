@_default:
  just _list | little_boxes --title "NixOS Configurations"

@_list:
  echo "These are the configs for all my NixOS systems"
  echo
  just --list

# Interactivly select a host and deploy to it
deploy:
  deploy-it

# Deploy configs to all hosts
deploy-all:
  deploy-it all
