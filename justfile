@_default:
  just _list | little_boxes --title "NixOS Configurations"

@_list:
  echo "These are the configs for all my NixOS systems"
  echo
  just --list

# Deploy configs to all machines
deploy:
  deploy -s
