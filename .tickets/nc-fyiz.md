---
id: nc-fyiz
status: open
deps: []
links: []
created: 2026-03-17T01:40:07Z
type: feature
priority: 2
assignee: Giovanni d'Amelio
---
# Create distributed Homer page definition module

Build a NixOS module that allows Homer dashboard entries to be defined alongside their service configs (e.g., in grafana.nix, jellyfin.nix) rather than centralized in homer.nix. Module should collect definitions via mkOption and merge them into the final Homer config.
