# CI builds the graph, not a Containerfile

`build-image.yml` now assembles the image with `just bst build oci/image.bst`
inside the pinned bst2 container, then loads the OCI layout into podman with
`podman pull -q oci:out` and retags it `localhost/<name>:<tag>`. That last step
is what keeps the change small: the shared `generate-tags`, `push-image` and
`sign-and-publish` reusables are untouched, because they only ever needed a
normal local image. The Containerfile build, the DNF cache, and the retry
wrapper are gone from this path.

Caching: the public read-only caches in `project.conf` cover the FSDK/GBM graph,
and `actions/cache` persists the local `~/.cache/buildstream` so our own elements
survive between runs. A writable remote cache is the follow-up
(`docs/research/06-ci-caching-personal-account.md`).

The new gate is `validate-bst.yml`: `bst show oci/image.bst --deps none` loads
every element without building. It is the check that would have caught both load
blockers from #19 in minutes instead of in a six-hour build — the
min-version/runner mismatch and the unloadable `signed-modules` element. A cheap
`bst show` gate is worth more than a fast build, because the expensive failure is
the one you find after the build starts.

Dakota alpha 6 (`docs/research/07`) is the reference for the next layer of work.
Its headline is chunkah ownership/rechunking, which **reverses #17's single-layer
decision** and needs a real build to validate; it is now ticket #39 rather than a
line item here. The CI-side alpha-6 items worth taking later: SBOM generation via
`buildstream-sbom`, server-side promotion with `skopeo copy --preserve-digests`,
and the build-progress renderer.

The full CI path has not run yet — the first real build tunes disk headroom and
the `podman pull oci:` load on the runner.
