---
id: nc-kblc
status: open
deps: []
links: []
created: 2026-03-17T01:13:52Z
type: task
priority: 2
assignee: Giovanni d'Amelio
---
# Update deploy script to use unique result paths for concurrent deploys

The deploy script currently uses a shared 'result' symlink for all builds. When running concurrent deploys to different hosts, this causes race conditions where one deploy can overwrite another's result symlink, leading to wrong configs being pushed to the cache or deployed.

Fix by using host-specific result paths (e.g., 'result-$host') so each deploy operates on its own isolated build output.

## Acceptance Criteria

- Deploy script uses unique result path per host (e.g., result-carbon, result-gallium)
- Concurrent deploys to different hosts do not interfere with each other
- Result symlinks are cleaned up after deploy completes
