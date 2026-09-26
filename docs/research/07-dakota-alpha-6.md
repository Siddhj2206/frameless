# Dakota alpha 6: what to take

Research note on the improvements in [Dakota Alpha 6](https://docs.projectbluefin.io/blog/dakota-alpha-6/)
(2026-09-22) and which of them frameless should adopt. Dakota alpha 6 is built
against **GNOME 51 and freedesktop-sdk 26.08.1** — the exact junctions frameless
pins — so its graph is the closest possible reference.

Primary sources: the announcement above; the local `~/Projects/dakota` tree at
`3d549f4`; the commit links in the announcement.

## The headline: chunkah

> "The chunka work is great, you'll notice way smaller updates than the old
> images."

Chunkah assigns **ownership metadata** to the composed image so the OCI layers
are chunked by content, which shrinks update downloads. In dakota it is a whole
pipeline, not a flag:

| Piece | Path | What it is |
| --- | --- | --- |
| Ownership element kind | `plugins/chunkah-ownership.{py,yaml}` | a **local** BuildStream plugin (`origin: local, path: plugins`) |
| Per-variant ownership | `elements/oci/chunkah/bluefin.bst`, `…/bluefin-nvidia.bst`, `…/brew-toolchain.bst` | `kind: chunkah-ownership`, declaring layer/provenance/metadata dependencies |
| Metadata tool | `elements/oci/chunkah-metadata-tool.bst` + `scripts/ownership_metadata.py` | finalizes ownership metadata into the OCI sandbox |
| Rechunk step | `just chunkify <image>` (~150 lines) | mounts the image, applies xattrs on a writable overlay, runs chunkah |
| Helper | `files/fakecap/fakecap-restore.c` | restores xattrs chunkah's raw syscalls bypass |
| CI | `publish.yml` "Chunkify image layers" | runs `just chunkify` before pushing |

**This reverses frameless's #17 decision** ("single layer, no chunkah"), and the
map lists "Layer/chunk strategy" as fog and "The Chunkah/ownership pipeline" as
out of scope. It is a build-graph change plus a local plugin plus a CI step, and
it is unverifiable without a full image build. It should be its own decision
ticket, not a line item in the CI ticket.

## CI and caching

- **Writable BST cache + remote execution.** `build.yml` generates a
  `buildstream-ci.conf` (`generate-bst-ci-config` action) with
  `enable-remote-execution: true` and `enable-push: true`, pointing at a CASD
  CAS with a client cert/key. It **fails closed**: if the console log lacks the
  "Remote Execution Configuration" banner, the job errors — a green cache hit is
  not proof the executor loaded. frameless cannot use dakota's CASD; research 15
  settled the personal-account options (public read-only CAS works
  unauthenticated; a writable cache needs `actions/cache` or a self-hosted
  REAPI).
- **Server-side promotion.** `publish.yml` re-tags with `skopeo copy` and
  `--preserve-digests`, so layers never leave the registry — "saving the 20–25
  min round-trip of the previous podman pull→tag→push approach".
- **SBOM.** A `buildstream-sbom` job, with its pip wheel cached by
  `actions/cache` keyed to the pinned commit SHA.
- **Build progress.** `files/scripts/bst-progress.py` renders `bst build`
  output with element counts, so a 330-minute build is legible in the log.

## Plumbing fixes worth copying

- **Compose the host toolchain once** per image build (`e4a2dfd`) rather than per
  step.
- **Do not use `/dev/stdin` for inline writes** under BuildBarn/BuildBox
  (`5e30bde`) — the remote executor does not provide it.
- **Preserve export mtimes** (`1c081c0`).
- **Fetch remote companion data before reading it** (`73ff57e`).

## Other alpha-6 changes

- **Single source of truth for the variant set**: `.github/image-variants.json`
  plus `.github/scripts/image_variants.py`, projected into each workflow's
  matrix with a gate that fails if `publish.yml` drifts. frameless has one
  variant, so the *pattern* matters more than the file; a multi-target catalog
  is out of scope.
- **Real stream tag in fastfetch** via a boot-time booted-image sync
  (`d4048c6`) — the workaround for dakota's baked `latest` tag. frameless's
  version is now real (#21), so it may not need this.
- **Kernel and bootc pinned ahead of the base**: `elements/core/linux-fdsdk.bst`
  (7.2.6 vs FSDK's 7.2.2) and `elements/gnomeos-deps/bootc.bst` (1.16.13 vs
  GBM's 1.16.6). frameless takes the FSDK default kernel (#17); a bootc pin may
  be needed at first build.

## Recommendation

- **#22 (CI, caching, validation)** — adopt the CI-side items: a BuildStream
  build workflow in the bst2 container, a writable artifact cache via
  `actions/cache`, fail-closed verification that the build actually ran,
  server-side promotion with `skopeo copy`, and SBOM generation as a follow-up.
- **New ticket** — chunkah ownership/rechunking, as a layer-strategy decision
  that reverses #17. It needs a full image build to validate, so it cannot be
  finished in the design phase.
