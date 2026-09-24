# Image size: where the bytes are, and the levers we deferred

Research note on how big frameless's image is, why, and which reductions we
chose not to take yet. It exists so the next person does not re-measure, and so
the deferred decisions have a home with their trade-offs attached.

Measured on the `:stable-testing` image published from `4400dbf`
(2026-09-24). The numbers are uncompressed unless stated; the compressed figure
is the one users actually download.

## Measurements

| | frameless | bluefin | bluefin-dx |
|---|---|---|---|
| Compressed | **3989 MB** | 3317 MB | 5269 MB |
| Uncompressed | **8314 MB** | — | — |
| Layers | 120 | 75 | 75 |

frameless sits between plain Bluefin and Bluefin-DX. **This is a normal size
for a full GNOME bootc image** — it is a whole OS, with every firmware blob,
every locale, and a kernel, not an app image.

Method: compressed total is the sum of the manifest's layer sizes; uncompressed
is `podman image inspect --format '{{.Size}}'`. The per-directory breakdown is
`du` on `podman image mount` output, run inside `podman unshare` (the mount
belongs to the rootless store, so it is not readable from the host directly).

## Where the bytes are

| Path | Size | Domain |
|---|---|---|
| `/usr/lib/x86_64-linux-gnu` | 1.4 GB | libraries (LLVM 110 M, WebKit 194 M, Mesa) |
| `/usr/lib/modules` | 1010 MB | kernel modules, `vmlinux` 489 M, `initramfs.img` 209 M |
| `/usr/lib/locale` | 991 MB | compiled locale directories (orphan) |
| `/usr/lib/firmware` | 941 MB | all hardware firmware |
| `/usr/share/doc` | 887 MB | `doc` |
| `/usr/share/locale` | 851 MB | `locale` |
| `/usr/bin` | 566 MB | binaries (podman alone 48 M) |
| `/usr/share/help` | 172 MB | `doc` |
| `/usr/share/man` | 139 MB | `doc` |
| `/usr/share/homebrew.tar.zst` | 143 MB | the bundled brew |
| `/usr/share/gtk-doc` | 57 MB | `doc` |
| `/usr/lib/python3.14` | 183 MB | Python |

The largest single file is `/usr/lib/modules/7.2.2/vmlinux` at 489 MB — the
**unstripped** kernel, debug symbols and all. The kernel that boots is
`vmlinuz`; `vmlinux` exists for crash-dump tooling, and runtime consumers read
`/sys/kernel/btf/vmlinux`, not the file.

## What the reference does

dakota's main-image compose excludes exactly what ours does — `devel`, `debug`,
`static-blocklist`. Beyond that it has one lever we lacked:

`elements/core/linux-fdsdk.bst` puts `vmlinux` and `System.map` in the
`devel`/`debug` domains, so the compose drops them:

```yaml
split-rules:
  devel:
    (>):
      - '%{indep-libdir}/modules/*/System.map'
  debug:
    (>):
      - '%{indep-libdir}/modules/*/vmlinux'
```

dakota can do this because it **replaces the kernel element**
(`freedesktop-sdk.bst` overrides `components/linux.bst → core/linux-fdsdk.bst`).

Everything else dakota does is small or not applicable: an `rm -rf` of
alsa-utils' man and locale; a build-only brew *toolchain* split from its runtime
closure; and `doc`/`locale` exclusions on separate minimal images
(`python-minimal`, `python-micro`) — not on the main one.

**dakota does not drop `doc` or `locale` from the main image.** The 1.25 GB of
docs and 1.84 GB of locale data are in Bluefin too. Those are product
decisions, not something the reference already solved.

## Decided and implemented

**Drop `vmlinux`/`System.map`** (~489 MB, no behaviour change).

FSDK 26.08 already declares `debug: vmlinux`, but frameless re-introduces the
file: `elements/kernel/unsigned-modules.bst` copies `/usr/lib/modules` into a
new element, and a copy loses the original's domains. The file arrives as an
*orphan*, and the compose's default `include-orphans: True` keeps it.

The fix re-declares the same split in that element, so the existing
`exclude: [devel, debug]` recognises it again. Implemented 2026-09-24; verify
`vmlinux` is absent and the image is ~0.5 GB smaller on the next full build.

## Decisions deferred

| Lever | Saves | Trade-off | Revisit when |
|---|---|---|---|
| Exclude the `doc` domain (`/usr/share/doc`, `man`, `help`, `gtk-doc`) | ~1.25 GB | no offline man/help; `--help` and in-app docs unaffected | someone wants a smaller download more than offline docs |
| Exclude the `locale` domain (`/usr/share/locale`) | 851 MB | translated strings for every non-English locale disappear | a fork ships single-language, or we accept English-only |
| Prune `/usr/lib/locale` (991 MB) | 991 MB | **not** covered by the `locale` domain — it is an orphan, so it needs `--prune`/`rm`, not an exclude. Removing it breaks non-C locales | same as above, and only with the archive's consumers checked |
| Prune `/usr/lib/firmware` | up to 941 MB | a universal image must boot unknown hardware; trimming means choosing targets | never for a general-purpose image |
| Compress `chunkah` output (`--compressed`) | none at rest | only avoids a recompress on push; registry size unchanged | not worth it |
| Lower `--max-layers` (120 → 64) | none | fewer layers means coarser deltas and worse OTA updates | not worth it |

Two mechanics worth remembering before attempting any of these:

- A compose `exclude` only matches files that a **domain** claims. A file that
  no split-rule matches is an orphan, and `include-orphans` (default true) keeps
  it. This is why `vmlinux` needed a split-rule and why `/usr/lib/locale` would
  need a prune rather than an exclude.
- `exclude` beats `include`: a file claimed by an excluded domain is dropped
  even if another domain also claims it
  (<https://docs.buildstream.build/master/elements/compose.html>).

## Also worth recording

The build telemetry reports **uncompressed** size only. The compressed figure —
what users download — is the one that matters for a "how big is our image"
question, and it is not currently surfaced. Adding it to the summary would need
either `skopeo inspect` on the pushed manifest or a sum of `podman push` output.

## Sources

- The published image itself: `ghcr.io/siddhj2206/frameless:stable-testing`,
  measured as described above.
- dakota at `~/Projects/dakota`: `elements/core/linux-fdsdk.bst`,
  `elements/oci/layers/bluefin.bst`, `elements/bluefin/unsigned-modules.bst`.
- BuildStream compose element reference —
  <https://docs.buildstream.build/master/elements/compose.html>.
- BuildStream default split-rules —
  `buildstream/data/projectconfig.yaml` in the pinned `bst2` container.
- freedesktop-sdk split-rules —
  `include/_private/split-rules.yml` at the pinned junction ref.
- Reference image sizes — the manifests of `ghcr.io/ublue-os/bluefin:latest`
  and `ghcr.io/ublue-os/bluefin-dx:latest`.
