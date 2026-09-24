# patches

Patches applied to a junctioned project, kept in sync with the project that
needs them.

`freedesktop-sdk/` is the same patch queue gnome-build-meta applies to
freedesktop-sdk. Our FSDK junction must match theirs exactly: a missing patch
makes the graph diverge from the public caches, and the affected elements rebuild
from source.

`freedesktop-sdk.manifest.json` records the patch hashes so drift is caught
offline.

```bash
just patch-sync          # re-fetch from gnome-build-meta at the pinned sha
just patch-drift-check   # verify offline
```

Run `patch-sync` after every gnome-build-meta junction bump.
