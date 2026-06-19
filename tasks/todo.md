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
- [x] 8. garage — 4 endpoints (s3/*.s3/*.web/admin) + 3 fleet.secrets (garage-{rpc-secret,admin-token,metrics-token}, hyphenated; settings paths updated) + dedicated user. garage-metrics-token also used by carbon prometheus (added in Task 24).
- [x] 9. immich — daemon (createDB on shared pg) + SQL metrics exporter + vhost with 3 /metrics/* proxy blocks (endpoint.extraConfig) + consul. prometheus scrape declared in Task 24 (carbon).
- [x] 10. jellyfin — jellyfin/prowlarr/sonarr/radarr/sabnzbd daemons + media group + QSV GPU + sabnzbd ExecStart override. 6 endpoints (nzbget consul.enable=false), 5 consul regs. Verified 10 total consul names match Blueprint.
- [x] 11. nats + send-metrics ported as shared aspects (gallium includes both; gallium owns nats-ws endpoint).
- [x] 11b. netdata-child brought forward (modules/hosts/gallium/netdata.nix) so monitoring survives the first cutover. Streams to the still-Blueprint carbon parent; api-key is a **manual fleet.secret with TEMPORARY `origin=gallium`** (carbon isn't a den host yet) — **deploy step: `credsync write netdata-api-key` on gallium with carbon's EXISTING key value** or the live parent rejects the stream. cronitor watchdog intentionally skipped. postgres collector + loginLimits restored. Drift: gallium-only. **Still BLOCKED-on-carbon:** fleet.nfs exports (mesh needs carbon as a den peer).
- [~] **Checkpoint (verified, NOT cut over):** evals clean · 54/54 fastest tests pass · **check-drv-drift now runs** (fixed: workspace+`path:` base instead of broken `git+file:?rev=`, optnix guard `mkIf`→`optionalAttrs`, per-host eval) → vs Phase-0 tip **only gallium drifts; cadmium/carbon/cesium/rhodium byte-identical** (no regression leaked from the 9 gallium commits). drv-diff vs baseline fully explained (deferred NFS/netdata + framework renders). Non-neovim system builds (70 ok); full toplevel build + cesium drvPath-IFD blocked ONLY by the pre-existing shared neovim kulala FOD (affects cadmium too — see [[neovim-kulala-fod-build-blocker]]). **nix/hosts/gallium NOT deleted, NOT deployed — awaiting goahead.**

## Phase 2 — carbon (~24 services)
- [ ] 12. carbon scaffolding (den.hosts, hw, disko, user, dns.serve, hammond net, consul webUi; **drop** read-only consul vhost). **Deferred infra here:** netdata-parent (+ pushover tokens) and **flip `netdata-api-key` origin `gallium`→`carbon`** + add the parent use-site (value stays identical — see Task 11b temp origin), send-metrics (reconcile w/ monitoring), nats owner (cluster + `nats-ws` fleet.services endpoint).
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
- [ ] 11b (carbon-phase). fleet.nfs mesh + exports (gallium↔carbon: forgejo /tank/forgejo, paperless-ngx /tank/paperless) — declare once carbon is a den host. netdata-child on gallium (api-key origin=carbon) + netdata-parent on carbon.
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
