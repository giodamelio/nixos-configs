@_default:
  echo "Nix Configurations"
  echo
  just --list

# Deploy configs to all machines
deploy:
  deploy -s
