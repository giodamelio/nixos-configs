# TODO: Migrate carbon & gallium into den

See `tasks/plan.md` for full task detail, acceptance criteria, and rationale.

## Phase 0 — Foundations (no host cutover)
- [ ] 0. Capture baseline drvs for carbon + gallium (`tasks/baseline/`)
- [ ] 1. Port pure-infra modules to aspects: send-metrics, nats, comin, netdata(parent/child), onepassword(server)
- [ ] 2. Settle + document decisions: envfiles · static net facts · dns-server host · consul topology
- [ ] **Checkpoint:** flake check green, baselines captured, decisions signed off

## Phase 1 — gallium (7 services)
- [ ] 3. gallium scaffolding (den.hosts, hw, ZFS filesystems, user, host facts) — no services
- [ ] 4. postgresql aspect (peer-auth base)
- [ ] 5. syncthing (pattern shakedown)
- [ ] 6. samba (SMB export + fw isolation)
- [ ] 7. attic (fleet.secrets envfile case)
- [ ] 8. garage (S3, multi-endpoint, 3 secrets) — carbon/gradient depends on this
- [ ] 9. immich (shared pg + metrics proxies + prometheus)
- [ ] 10. jellyfin (5 daemons, media group, GPU)
- [ ] 11. fleet.nfs exports (forgejo-repos, paperless) — carbon depends on this
- [ ] **Checkpoint:** drv parity → delete `nix/hosts/gallium/` → flake check → deploy → human review

## Phase 2 — carbon (~24 services)
- [ ] 12. carbon scaffolding (den.hosts, hw, disko, user, dns.serve, hammond net, consul webUi, GET-only consul vhost no-mtls)
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
