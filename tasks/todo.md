# TODO: Migrate carbon & gallium into den

See `tasks/plan.md` for full task detail, acceptance criteria, and rationale.

## Phase 0 — Foundations (no host cutover)
- [x] 0. Capture baseline drvs for carbon + gallium (`tasks/baseline/`)
- [x] 1. Port pure-infra modules to aspects — **comin only**. nats/send-metrics/netdata each carry a fleet-modeling decision (endpoint ownership / monitoring overlap / shared secrets) and are **deferred into the host tasks** (3 gallium, 12 carbon) where they're drift-testable.
- [x] 2. Decisions settled: envfiles→decompose · dns-server→carbon+gallium · consul vhost→dropped · network→dynamic/CNAME (no static facts) · bootstrap_expect→auto-derived · stateVersion→25.11
- [x] **Checkpoint:** baselines captured, comin landed (rhodium eval clean), decisions signed off → Phase 0 complete

## Phase 1 — gallium (7 services)
- [x] 3. gallium scaffolding (den.hosts + hw + ZFS fs + server user + facts: role/consul/dns.serve/static-network/zfs_backup/firewall). Evals clean. **Network corrected to static** (den aspects need it). **Deferred infra → Task 11:** netdata-child, send-metrics, nats.
- [x] 4. postgresql aspect (base server + pgcli; shared, included by gallium)
- [x] 5. syncthing — fleet.services pattern validated (caddy vhost + consul reg match Blueprint). NOTE: endpoint needs explicit `backend.host="localhost"` (null isn't auto-resolved).
- [x] 6. samba — SMB share + LAN fw on enp5s0 + consul TCP check (no endpoint; explicit consul address/port).
- [x] 7. attic — fleet.secrets credential use-site (LoadCredentialEncrypted dropin on atticd) + atticd.environmentFile points at the cred path (replaces the envfile shell-wrapper; flat KEY=value assumed). Endpoint+consul. atticadm wrapper kept verbatim.
- [ ] 8. garage (S3, multi-endpoint, 3 secrets) — carbon/gradient depends on this
- [ ] 9. immich (shared pg + metrics proxies + prometheus)
- [ ] 10. jellyfin (5 daemons, media group, GPU)
- [ ] 11. fleet.nfs exports (forgejo-repos, paperless) — carbon depends on this
- [ ] **Checkpoint:** drv parity → delete `nix/hosts/gallium/` → flake check → deploy → human review

## Phase 2 — carbon (~24 services)
- [ ] 12. carbon scaffolding (den.hosts, hw, disko, user, dns.serve, hammond net, consul webUi; **drop** read-only consul vhost). **Deferred infra here:** netdata-parent (fleet.secrets api-key shared→gallium + pushover tokens), send-metrics (reconcile w/ monitoring), nats owner (cluster + `nats-ws` fleet.services endpoint).
- [ ] 13. postgresql aspect
- [ ] 14. pocket-id (OIDC provider — runtime dep of many)
- [ ] 15. mealie
- [ ] 16. miniflux
- [ ] 17. loki
- [ ] 18. grafana (rewrite credentialPath reference)
- [ ] 19. openbao
- [ ] 20. home-assistant (+ zwave-js, serial)
- [ ] 21. netdata parent (+ cronitor)
- [ ] 22. node-hp-scan-to
- [ ] 23. homer (reconcile generated dashboards vs hand-written)
- [ ] 24. prometheus server (fleet scrape set; after gallium)
- [ ] 25. gatus status page
- [ ] 26. forgejo (+ runner; needs gallium NFS + OIDC)
- [ ] 27. paperless (NFS + OIDC + gotenberg; envfile case)
- [ ] 28. solidtime (PHP-FPM + app key)
- [ ] 29. grist (container + OIDC)
- [ ] 30. windmill (container workers + DB)
- [ ] 31. restate (deployedApps DI)
- [ ] 32. hooks (webhook relay)
- [ ] 33. gradient (hardest; needs forgejo + garage + restate + hooks)
- [ ] 34. yesman + eater-of-feeds (deployedApps)
- [ ] **Checkpoint:** drv parity → delete `nix/hosts/carbon/` → flake check → deploy → human review

## Phase 3 — Cleanup
- [ ] 35. Remove dead Blueprint modules + docs/mtls.md; update AGENTS.md/CLAUDE.md; deadnix/statix clean
