---
name: troubleshooting
description: >-
  Symptom to cause to fix for build, CI, and runtime failures, plus the
  pre-commit checklist. Use when something is broken or before opening a pull
  request.
---

# Troubleshooting

## Before a pull request

- [ ] Conventional Commit message.
- [ ] `just lint` — shellcheck on every tracked script.
- [ ] `just check` — Justfile syntax.
- [ ] `just test-unit` — the suite.
- [ ] `just validate-brewfiles` / `just validate-flatpaks` if those changed.
- [ ] `just bst show oci/image.bst --deps none` if the graph changed.

CI runs the same checks; running them locally only makes the pull request quiet.

## Build

| Symptom | Cause | Fix |
|---|---|---|
| `Version mismatch` at project load | `project.conf`'s `min-version` is newer than the BuildStream in the pinned `bst2` container | move them together: bump the container digest, or lower `min-version` |
| `Specified path 'files/…' does not exist` at load | an upstream element needs a file that is not in the public repository | override that element at the junction with your own (see `kernel/unsigned-modules.bst`) |
| `Unexpected key: …` from an `(@)` include | the include was merged at the element top level | merge it into `variables:` — `variables: (@): [include/fsdk-version.yml]` |
| `Unexpected key: …` in `project.conf` | a variable was written outside `variables:` | move it under `variables:` |
| an element cannot find `sh`, `cp`, or `mkdir` | freedesktop-sdk 26.08's `runtime-minimal` carries no shell | `build-depends: core/sandbox-tools.bst` |
| `ninja: fatal: posix_spawn: Resource temporarily unavailable` | unbounded parallel jobs exhaust the runner's process limit | cap them in `buildstream.conf` (`scheduler.builders`, `build.max-jobs`) |
| an SDK element (`sdk/gtk`, `sdk/webkit2gtk`) rebuilds from source | the graph diverged from the public caches | make the junction match gnome-build-meta exactly: the `patches/freedesktop-sdk` queue and every override |
| *one* upstream element rebuilds although the junction matches | its key depends on a file gnome-build-meta's CI generates at build time, which a clean checkout lacks | reproduce that file with a patch queue (see `patches/gnome-build-meta` for the boot-key cert) |
| builds never get warmer; the cache package is empty | `Save cache` failed, or `clean.yml` pruned the package | check the `Save cache` step; the package is `ghcr.io/<owner>/<repo>-cache` and `clean.yml` keeps it 2 days |
| `Overlaps detected` between two elements | both install the same path | add it to one element's `public.bst.overlap-whitelist` |
| a build command works locally but fails on CI | the remote sandbox differs (no `/dev/stdin`, no network) | write to a file instead of `/dev/stdin`; declare every build input |
| a change rebuilds the world | the change invalidated a widely-depended-on element | expected; the graph is content-addressed. Build the one element first |

`just bst show <element>` and `just bst artifact log <element>` are the two
cheapest diagnostics. `just bst artifact delete <element>` drops a bad artifact.

## CI

| Symptom | Cause | Fix |
|---|---|---|
| `validate` never runs | branch protection names a check no workflow produces | the context must be exactly `validate` |
| `validate-bst` fails | the graph does not load | run `just bst show oci/image.bst --deps none` locally |
| a re-run rebuilds the whole graph instead of reusing artifacts | the cache did not restore. Read the `Restore cache` log: `No usable cache … starting cold` means the pull failed, and every element is then pulled from upstream again | `scripts/bst-cache-oci.sh` now retries the pull three times and prints oras's error; if it still fails, check the cache package exists and GHCR is reachable. A restored cache re-runs the same graph in minutes, rebuilding only what changed |
| a big rebuild costs 70 min although nothing changed | a failed cache pull degrades to a cold build, silently and by design — the cache is an optimisation, so `continue-on-error` swallows it | read the `Restore cache` step's log, not the job conclusion; the step succeeds even when it starts cold |
| `Push to GHCR` fails with `StatusCode: 400` mid-upload | a transient GHCR edge failure during a chunked layer upload. A healthy push is ~2 min; this one runs 15+ before dying, and the body is an HTML error page rather than JSON | re-run the failed job — the build and cache are intact, so only the push repeats. Neither retry layer catches it: `buildah --retry` ignores 4xx, and `push-image`'s own loop cannot fire on a *failed* push because the script runs under `set -e` and the push is a bare command. That is a bug in `projectbluefin/actions`, not here |
| Renovate opens nothing | `RENOVATE_TOKEN` is missing or lacks the `workflow` scope | recreate the token |
| the promotion PR never opens | `stable` does not exist | create the branch |
| the promotion PR will not merge | `stable` requires an approval | set required approvals to 0 |
| a Renovate PR waits forever | auto-merge is off | enable it in Settings |

## Runtime

| Symptom | Cause | Fix |
|---|---|---|
| `ujust` shows no custom commands | `60-custom.just` was not written or imported | check that `custom/custom.bst` copied it and Common's `00-entry.just` imports it |
| no Flatpaks on first boot | the preinstall service ran before the network | reboot once online; it does not retry that boot |
| no `brew` | the tarball was not staged | check `runtime/brew-tarball.bst` built and `brew-setup.service` is present |

## Capturing what you learned

When a fix here was non-obvious, put it in the skill that owns the area, in the
same pull request. That is the only home for durable learning.
