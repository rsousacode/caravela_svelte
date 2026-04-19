# Upstream sync log

This fork tracks [live_svelte](https://github.com/woutdp/live_svelte)
for security patches and upstream improvements.

## Last synced

- **Upstream version:** v0.18.0 (Hex: `live_svelte 0.18.0`)
- **Sync date:** 2026-04-19
- **Sync method:** copied source from `deps/live_svelte/` of a
  consumer project (`caravela_demo`). Not a git-level fork — the
  fork was bootstrapped from the Hex release tarball that ships
  in `deps/`, which matches the v0.18.0 tag.

## Re-sync procedure

When upstream ships a new release:

1. `cd /tmp && git clone https://github.com/woutdp/live_svelte live_svelte_upstream`
2. `git -C live_svelte_upstream diff v0.18.0 v<NEW> -- lib assets test > /tmp/upstream.patch`
3. Apply the patch to the fork with the renames flipped:
   ```bash
   sed 's/LiveSvelte/CaravelaSvelte/g; s/live_svelte/caravela_svelte/g' \
     /tmp/upstream.patch | git apply -p1 --directory=.
   ```
4. Resolve conflicts (expect conflicts in `live.ex`, `ssr.ex`,
   anything we've refactored).
5. Update this file with the new version and SHA.
6. Run `mix test`; fix breakage.
7. Tag the fork with a matching version bump.
