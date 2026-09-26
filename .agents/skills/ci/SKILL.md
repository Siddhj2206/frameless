---
name: ci
description: >-
  GitHub Actions, Renovate, the two-branch release model, signing, and
  promotion. Use when changing workflows, dependency policy, or releasing.
---

# CI

## Workflows

| Workflow | Trigger | Does |
|---|---|---|
| `build-image.yml` | push to `main`, dispatch | Builds with BuildStream, signs, and pushes the image. |
| `execute-release.yml` | push to `stable` | Promotes the candidate digest. Does not rebuild. |
| `promote-main-to-stable.yml` | daily schedule, dispatch | Opens the squash promotion PR and runs the release gate on it. |
| `sync-stable-to-main.yml` | push to `stable` | Merges `stable` hotfixes back into `main`. |
| `pr-validation.yml` | pull request | The `validate` check: `just check`, shellcheck, pre-commit. |
| `validate-bst.yml` | push, pull request (elements changed) | Loads the image graph with `bst show`. |
| `validate-brewfiles.yml` | pull request | Brewfiles, without evaluating them. |
| `validate-flatpaks.yml` | pull request | Flatpak preinstall files against Flathub. |
| `validate-justfiles.yml` | pull request | `just check`. |
| `validate-renovate.yml` | pull request | Renovate config. |
| `unit-tests.yml` | push, pull request | The bats suite. |
| `renovate.yml` | schedule, config change | Runs Renovate. |
| `track-bst-sources.yml` | weekly schedule, dispatch | Refreshes BuildStream refs with `bst source track`, one PR per group. |
| `clean.yml` | daily schedule | Prunes old images and the cache package. |

Most are thin callers of reusable workflows in `projectbluefin/actions`.

## The release model

`main` publishes `:stable-testing`. `stable` never rebuilds: promotion is a
squash PR from `main` to `stable`, and `execute-release.yml` copies the digest
`:testing` resolves to. The README owns the release table and the promotion
gate's current limits.

The factory reusable puts its release gate and its auto-merge enrollment behind
one input, `enqueue_promotion`. A personal repository cannot enroll — there is no
merge queue, and `gh pr merge --auto` refuses without a merge method — so
enrollment is off, and `promote-main-to-stable.yml` runs the gate itself in its
own `gate` job to keep the pre-merge check. That gate resolves `:testing` when it
runs, so it attests the current candidate. The binding comes from
`execute-release.yml` passing `source_branch: main`, which makes the reusable
refuse to promote at all once `main` has moved past the promotion commit; a
manual dispatch is exempt, because that path is deliberate recovery.

The same reusable builds the squash branch, and it stages deletions with
`git diff --diff-filter=D`. Git reports a moved file as a rename, so a path `main`
moved survives on its old path and the branch's tree stops matching `main`'s —
the state the guard above refuses, but only after the PR is merged.
`repair-promotion-branch` in `promote-main-to-stable.yml` rebuilds the branch from
`main`'s tree when it has drifted, and the `validate` check fails a promotion PR
whose tree does not match `main`. The sweep belongs to `projectbluefin/actions`;
the one-line fix there is `--no-renames`.

## The BuildStream build

`build-image.yml` assembles the image with `just bst build oci/image.bst` inside
the pinned bst2 container, then loads the OCI layout into podman
(`podman pull -q oci:out`) so the shared tag/push/sign reusables are unchanged.
There is no Containerfile anywhere in the repository.


Caching: `project.conf` lists three public **read-only** caches (gbm.gnome.org,
cache.projectbluefin.io, cache.freedesktop-sdk.io) that we pull from and never
push to. Our own CAS travels as a single OCI artifact on GHCR (`<repo>-cache`),
moved by `scripts/bst-cache-oci.sh` and wrapped by `just cache-pull` /
`just cache-push`. Push writes `:latest` on every run, success or failure, so a
failed build still warms the next one, and the graph-key tag only when the
caller passes one — the workflow does, on success, so a matching graph can be
preferred. Both workflow steps are `continue-on-error`: the cache is an
optimisation, and a cold start is always valid. `clean.yml` prunes the package
on a shorter clock than the images. The delta-selection optimisation is
`docs/research/10-remote-availability-cache-pruning.md`.

`validate-bst.yml` runs `bst show oci/image.bst --deps none`. It loads the whole
graph without building, so a load error fails in minutes rather than in the
six-hour build. This is the gate that catches a junction bump whose upstream
element cannot load in a fork (the `signed-modules` class of failure).

## Versioning

The image version comes from the FSDK junction ref. `just` parses it to
`fsdk_version`, `just bst` writes `include/fsdk-version.yml`, and os-release and
the OCI labels read `%{fsdk-version}`. `just tags` prints the minor stream
(`26.08`) and the exact release (`26.08.1`). Bumping the junction moves the
version; there is no second edit.

## Signing

Keyless OIDC via Cosign. There are no keys to generate or store; the workflow
needs `id-token: write` and `packages: write`. Unsigned images fail the promotion
gate. The README has the command to verify an image.

## Renovate

Self-hosted through `projectbluefin/actions`, running every six hours. The policy
lives in `.github/renovate.json`. Non-major GitHub Actions updates are grouped
into one pull request and automerge once checks pass; majors wait for a human.
OSV vulnerability alerts are on.

Renovate owns what it has a datasource for: GitHub Actions, pre-commit hooks,
and container digests — the `bst2` runner in the Justfile, plus any version
annotated with a `# renovate:` comment. It does **not** own BuildStream refs:
`track:` is BuildStream's own symbolic-tracking field and only `bst source track`
resolves it, across git, docker, and pypi sources alike. `just track` runs that,
grouped by element directory, and `track-bst-sources.yml` opens one pull request
per group so a junction bump never rides along with a cheap runtime bump. There
is deliberately no `.bst` Renovate manager: one would match nothing and imply an
ownership Renovate does not have. The evidence is
`docs/research/11-renovate-config.md`.

The tracker force-pushes `auto/track-bst-<group>` with a lease, so it fetches the
branch first: the CI checkout carries no remote-tracking ref for it, and
`--force-with-lease` refuses to push without one (`stale info`). The original
single-PR version had the same latent bug; it only worked because it never ran
twice.

frameless does not extend `projectbluefin/renovate-config`. It is a template: a
fork must not inherit another organisation's dependency policy, so the patterns
are copied deliberately and the config stays self-contained.

The `bst2` runner digest never automerges: it must stay at least as new as
`project.conf`'s `min-version`, and the image must build first.

Renovate needs the `RENOVATE_TOKEN` secret and auto-merge enabled. Both are
onboarding steps.

Automerge deliberately covers GitHub Actions SHA bumps, which reverses a guard
upstream kept. Those SHAs run in jobs holding `packages: write`,
`id-token: write`, and `secrets: inherit`, and PR builds are disabled, so a bump
merges with only shellcheck, just check, and the test suite having run. Putting the
guard back is one rule — `matchManagers: ["github-actions"]` with
`automerge: false`.

## Making a change

1. Open a pull request against `main`.
2. Wait for `validate`, `validate-bst`, and the image build.
3. Merge. `main` publishes `:stable-testing`.
4. Review and merge the promotion PR to publish `:stable`.
