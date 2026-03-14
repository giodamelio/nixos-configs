# TODO

- [ ] Setup comein for better keeping systems up to date.
- [ ] **2026-08-25**: Check if [tree-sitter-surrealdb.nvim](https://github.com/DariusCorvus/tree-sitter-surrealdb.nvim) has been updated for the new nvim-treesitter API. Re-add SurrealDB syntax highlighting if compatible. (Removed in Feb 2026 due to incompatibility with nvim-treesitter rewrite)
- [x] Fix reboot-into-entry script so I can call it from anywhere and add a .desktop shortcut for it.
  - Added .desktop entry makes it discoverable by Vicinae and any XDG-compliant launcher.
- [ ] Setup mTLS for Caddy. Just for services that only I will use from the browser as an extra layer of protection
- [x] Install Miniflux
- [x] Move the Prometheus scrape configs to be next to the config of the services. To enable loading dynamically with modules. The high level config should still stay in the prometheus.nix
