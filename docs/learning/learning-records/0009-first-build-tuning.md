# The first real build: three tuning lessons

The graph loaded and every element built in isolation, but the first full CI
build surfaced three things the design phase could not.

## 1. A shared runner needs the parallel jobs capped

Both failing elements died with `ninja: fatal: posix_spawn: Resource temporarily
unavailable` — a process-limit exhaustion, not a compile error. An unbounded
BuildStream build spawns far more processes than a shared runner allows
(`scheduler.builders` × `build.max-jobs` × LTO children). `buildstream.conf`
caps them and CI passes it via `BST_FLAGS`. The lesson: a build config is part of
the CI wiring, not an optimisation.

## 2. A junction must match the project it junctions, exactly

The build then rebuilt the GNOME SDK (`sdk/gtk`, `sdk/webkit2gtk` — the latter is
~8,900 compile steps) from source. The cause: frameless's freedesktop-sdk
junction differed from gnome-build-meta's own in two ways — it lacked the
`patches/freedesktop-sdk` patch queue and it was missing the `zenity`,
`linux-module-cert` and `libical` overrides. Either makes the graph diverge from
the artifacts published in the public caches, and everything built on top
rebuilds. The lesson: when you junction a project, copy its junction's sources
*and* its full override list; a "close enough" list is a cold build. `just
patch-sync` / `patch-drift-check` keep the patch queue honest.

## 3. `actions/cache` does not save a failed build by default

The repository had no `bst-*` cache at all — only the old finpilot `buildah-*`
ones. `actions/cache`'s post-step writes only when the job succeeds unless
`save-always: true`, and every BuildStream build had failed. So every run started
cold. With `save-always`, a failed build still caches what it built.

The residual limit is structural: GitHub caps a repository's cache at 10 GB (a
full GNOME CAS is larger), and a personal account has no writable remote CAS as
dakota does. Build duration is therefore dominated by how much the public caches
already hold — which is why lesson 2 matters more than any cache tuning.
