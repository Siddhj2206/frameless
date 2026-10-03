# Renovate and BuildStream refs: what each can own

Research note on whether BuildStream refs can be tracked natively by Renovate,
written because the answer decides how much bespoke machinery frameless carries
and whether a fork inherits it. The conclusion is that `bst source track` is the
resolver and Renovate is not, and the note records the evidence so nobody
re-derives it — the wrong answer was already reached once, in a commit whose
premise was a misread size measurement.

Read 2026-09-25 against Renovate 44 and the family's configs.

## The question

frameless pins seven sources across five elements. Renovate owns GitHub Actions
and container digests; something has to own the rest. Could that be Renovate too
— one system instead of two?

## What the family does

| Repo | BuildStream refs | Renovate managers |
|---|---|---|
| `projectbluefin/dakota` | `track-bst-sources.yml`: a matrix, one job per element, one branch `auto/track-<name>` per element, grouped `auto-merge` / `manual-merge` / `core-junctions` / `tarballs`; a separate `track-next-junctions.yml` | `github-actions` only — BuildStream refs are explicitly Renovate's *not* to touch |
| `projectbluefin/bluefin` | same tracker | `github-actions` + `custom.regex` for Justfile, `image-versions.yml`, `.gitmodules` |
| `projectbluefin/common`, `bluefin-lts` | same tracker | `github-actions` + `custom.regex` for Containerfile pins |
| `projectbluefin/actions`, `ublue-os/image-template` | n/a | `github-actions` |

Nobody tracks a `.bst` ref with Renovate. dakota goes further and *narrows*
Renovate to `github-actions` so it cannot try.

## Can Renovate track a git ref at all?

Yes, and better than expected. Renovate has a `git-refs` datasource, documented
for exactly this case ("update git-based dependencies that are not natively
supported"), which returns the head of a named ref when you put the ref in
`currentValue` and match on `currentDigest`.

It is not limited to GitHub. The implementation shells out to `git ls-remote`
against the `packageName` URL (`lib/modules/datasource/git-refs/base.ts`:
`createSimpleGit(...).listRemote([...])`), so any reachable host works —
`gitlab.freedesktop.org` and `gitlab.gnome.org` included. That removes the
obvious blocker.

## What it still cannot do

| Pin | Kind | `track:` | Renovate? |
|---|---|---|---|
| `freedesktop-sdk` | git junction | glob `freedesktop-sdk-26.08*` | No — `git-refs` names one ref; a glob is not a ref |
| `gnome-build-meta` | git junction | branch `gnome-51` | Not usefully — see below |
| `runtime/common` | git | branch `main` | Not usefully — see below |
| `runtime/brew` | git | branch `main` | Not usefully — see below |
| `plugins/buildstream-plugins` | pypi tarball | — | No — `ref:` is a file sha256 and the URL is a hashed path Renovate cannot rewrite |
| `plugins/buildstream-plugins-community` | pypi tarball | — | No, same |
| `runtime/brew-tarball` | docker | `latest` | No — per-arch manifest digests under a `(?):` conditional; `bst source track` resolves each arch |

Four of seven have no Renovate datasource at all. The three git ones fail for a
subtler reason:

1. **The ref format differs.** `bst source track` writes a git-describe ref —
   `v2026.08-112-g8df20e8086…`, `51.0-3-ge34f1eb8c1…`. `git-refs` returns a
   plain 40-hex commit. The captured digest (a describe string) never equals the
   branch head, so Renovate would see an update due on every run.
2. **The ref string is part of the cache key.** BuildStream's `SourceRef` is
   included in the source's unique key (`buildstream.source`: "the source's
   SourceRef must be considered as a part of that key"), so the two mechanisms
   disagreeing means a rebuild each time they alternate — and `bst source track`
   would rewrite Renovate's plain SHA back to describe form.
3. **It duplicates `track:`.** Renovate would need the branch name spelled out
   per element in `.github/renovate.json`, a second source of truth beside the
   element's own `track:`. A fork that adds or renames an element edits Renovate
   config by hand. That is the opposite of a template.

`track:` is BuildStream's symbolic-tracking field, and `Source.track()` exists
to resolve it (`buildstream.source`: "Resolve a new ref from the plugin's track
option"). `bst source track` is the only implementation that understands it,
across every source kind.

## What was decided

- **`bst source track` stays the resolver.** It is BuildStream-native and
  source-kind-agnostic, and it produces the canonical ref.
- **The wrapper is derived, not listed.** `scripts/bst-track-groups.sh` reads
  the tree: an element is trackable when a source declares `track:`, and its
  group is its directory under `elements/` (a root element is its own group). A
  fork maintains nothing. The old hardcoded list was already wrong — it named
  two plugin elements whose sources are pinned outright and have no `track:` to
  move.
- **One pull request per group.** `track-bst-sources.yml` loops the groups and
  opens `auto/track-bst-<group>`, so a junction bump — which changes the cache
  key of everything beneath it and rebuilds from source — never rides along with
  a cheap runtime bump.
- **Renovate's config stays native.** Its managers are the real ones
  (`github-actions`, `pre-commit`, `docker`); the `.bst` `# renovate:` custom
  manager is gone, because it matched nothing and implied an ownership Renovate
  does not have.

## Sources

- Renovate, `git-refs` datasource — <https://docs.renovatebot.com/modules/datasource/git-refs/>
- Renovate, `git-refs` implementation (the `git ls-remote` call) —
  <https://github.com/renovatebot/renovate/blob/main/lib/modules/datasource/git-refs/base.ts>
- BuildStream, `Source.track()` and the source ref —
  <https://docs.buildstream.build/master/buildstream.source.html>
- dakota's tracker and Renovate config —
  <https://github.com/projectbluefin/dakota/blob/main/.github/workflows/track-bst-sources.yml>,
  <https://github.com/projectbluefin/dakota/blob/main/.github/renovate.json5>
- The org's shared config —
  <https://github.com/projectbluefin/renovate-config/blob/main/org-inherited-config.json>
