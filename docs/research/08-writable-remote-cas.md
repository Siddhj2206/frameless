# A writable remote CAS for frameless

Research note on giving frameless a **writable** remote artifact cache, so our own
elements are pushed once and pulled thereafter instead of rebuilt on every run.
It extends `docs/research/06-ci-caching-personal-account.md`, which established
that the public caches are read-only and that a personal account has no
`projectbluefin` CAS credentials.

**Constraint: everything stays on GitHub.** No VPS, no homelab, no
self-hosted service. That reframes the question from "which REAPI server" to
"can GitHub itself hold the cache" — see *GitHub-native alternatives* below. The
server survey is kept because it explains why a real remote CAS cannot live on
GitHub, and what to do if the constraint is ever lifted.

## The requirement, precisely

BuildStream's cache-server docs are explicit about what a server must implement:

> "BuildStream relies on the **ContentAddressableStorage** protocol … in concert
> with the **remote asset protocol** in order to assign symbolic labels (such as
> artifact names) to identify stored content. As such, BuildStream is able to
> function with any implementations of these two services."
> — <https://docs.buildstream.build/master/using_configuring_cache_server.html>

So a compatible server must speak **both** REAPI CAS **and** the Remote Asset
API. That second one is what BuildStream calls the *index*; the CAS is the
*storage*. BuildStream's user config requires both, or it will not push:

> "When configuring cache servers, BuildStream will require both storage and
> indexing capabilities, otherwise no attempt will be made to fetch or push data
> to and from cache servers."
> — <https://docs.buildstream.build/master/using_config.html>

This is the constraint that rules most "bazel remote cache" tools out.

## Which servers actually work

### Buildbarn — the one BuildStream documents

BuildStream's docs name **Buildbarn** and give a docker-compose manifest:
`bb-storage` is the CAS/storage listener and `bb-remote-asset` is the index:

```yaml
# artifacts:
#   - url: https://localhost:7981   # index
#     type: index
#     push: true
#   - url: https://localhost:7982   # storage
#     type: storage
#     push: true
```

Two services, jsonnet configuration, docker-compose provided. The
authoritative reference, and the heavier option.

### NativeLink — the simplest working server

NativeLink has a first-class BuildStream guide and a runnable integration test
(`integration_tests/buildstream/`). One listener serves "CAS, Action Cache,
execution, capabilities, ByteStream, **fetch, and push**" — CAS *and* the Remote
Asset API. The BuildStream config is short:

```yaml
artifacts:
  servers:
    - url: http://host:50051
      push: true
```

It ships as a single binary / container (`ghcr.io/tracemachina/nativelink`),
supports filesystem, S3, R2, GCS and Azure storage backends, and TLS with client
certificates. For a single-node personal cache this is the least machinery.

### bazel-remote — does **not** fit

It is the most tempting (one Go binary, disk with LRU, S3/GCS/Azure backends,
Docker image), and it implements CAS, Action Cache, Capabilities and ByteStream
over gRPC. But its Remote Asset API support is "**(very) experimental support for
a subset of the Fetch service**", enabled behind a flag and aimed at Bazel's
remote downloader. BuildStream needs the asset **Push** service to label
artifacts, which bazel-remote does not provide. **Rule it out.**

`buildbox-casd` is a local CAS daemon, not a shared server, and does not solve
this either.

## Authentication

BuildStream's `auth` block accepts either an HTTP **bearer token**
(`access-token`) or **mTLS** (`client-cert` + `client-key`):

```yaml
artifacts:
  servers:
    - url: https://cache.example.com:11001
      type: all
      push: true
      auth:
        client-cert: /src/cache-client.crt
        client-key: /src/cache-client.key
      connection-config:
        keepalive-time: 60
        retry-limit: 5
        retry-delay: 1000
        request-timeout: 300
```

Never stand up an anonymous, publicly writable CAS: BuildStream's own guidance is
that uploads "should normally not allow" being unauthenticated, and an open
writable cache is a cache-poisoning target. mTLS is the portable choice here —
NativeLink and Buildbarn both support it, and BuildStream has first-class fields
for it.

## GitHub-native alternatives (no server)

The project keeps everything on GitHub, so a self-hosted REAPI server is out.
What GitHub itself offers:

| Store | Shape | Limit | Cost beyond the free tier |
| --- | --- | --- | --- |
| **Actions cache** | a *directory* cache (`~/.cache/buildstream`), not a CAS protocol | 10 GB per repo free; **user-owned repos can raise it to 10 TB** | **$0.07/GB/month** (50 GB ≈ $2.80, 200 GB ≈ $13.30) |
| GHCR / GitHub Packages | an OCI artifact holding the cache tarball | shares the artifact allowance (500 MB free on Free, 1 GB Pro) | **$0.25/GB/month** — worse for bulk data |
| Releases / artifacts | a tarball per release | 2 GB per asset; artifacts expire | — |

**There is no GitHub-hosted REAPI/CAS service.** GitHub cannot host the
protocol-level cache BuildStream speaks, so the GitHub-native equivalent is
*"a bigger `actions/cache`"*, not a real remote CAS.

Raising the Actions cache limit is a repository setting that needs a payment
method on file and an opt-in in the Actions settings; cache storage is billed
separately from artifacts and packages, and only above the included 10 GB.
Sources: GitHub dependency-caching reference
(<https://docs.github.com/en/actions/reference/workflows-and-actions/dependency-caching>)
and Actions billing
(<https://docs.github.com/en/billing/concepts/product-billing/github-actions>).

### The catch that makes it cheaper than it looks

The local `~/.cache/buildstream` is large mostly because it also holds every
artifact **pulled** from the public caches — the GNOME SDK and the whole
freedesktop-sdk/gnome-build-meta graph. Those are re-pullable and need not be
cached at all. BuildStream offers no way to cache only the artifacts *we* built;
`cache.storage-service` moves content to a remote storage service, which is the
thing we cannot host.

So the honest sizing question is: how big is the cache once the public-cache
content is excluded? frameless's own elements are small. If that is a few GB, the
free 10 GB cache holds it and **nothing needs to change but `save-always`**.

## Recommendation

**Decision: stay on the Actions cache.** No self-hosted REAPI server.

1. `actions/cache` on `~/.cache/buildstream` with `save-always: true` is the
   writable cache. It is a directory cache, not a protocol cache — BuildStream
   sees a warm local CAS and does the rest.
2. If the cache outgrows the free 10 GB, raise the repository's Actions cache
   limit (a payment method plus the Actions settings opt-in; up to 10 TB, billed
   at $0.07/GB/month above 10 GB).
3. Design against the **6-hour per-job cap** — see below. That is the number that
   matters, not minutes.
4. The self-hosted server survey above stays only as the record of why a real
   remote CAS cannot live on GitHub, and what to do if the constraint is ever
   lifted.

## The hard limits that still apply

Minutes are free and unmetered on public repositories that use standard
GitHub-hosted runners, so a public repo is not billed for build time. "No
runtime limit" is still false — these are hard caps:

| Limit | Value | Increasable |
| --- | --- | --- |
| **Job execution time** (GitHub-hosted) | **6 hours** | no |
| Workflow run time (incl. waiting) | 35 days | no |
| Concurrent jobs (standard runner, Free plan) | 20 | support ticket |
| Runner disk | ~14 GB free | no |
| Actions cache storage | 10 GB free; up to 10 TB configurable for user-owned repos | by configuration, billed above 10 GB |
| Cache uploads / downloads | 200 / 1500 per minute | no |

The 6-hour job cap is the one to design against: a cold full build that rebuilds
the GNOME SDK approaches it, which is why junction parity and the warm cache are
not optional. `build-image.yml` sets `timeout-minutes: 360` to match the cap.
Sources: <https://docs.github.com/en/actions/reference/limits> and
<https://docs.github.com/en/billing/concepts/product-billing/github-actions>.

## Sources

- BuildStream, Configuring Cache Servers (CAS + remote asset; Buildbarn
  docker-compose): <https://docs.buildstream.build/master/using_configuring_cache_server.html>
- BuildStream, User configuration (`artifacts.servers`, `type`, `push`, `auth`,
  `connection-config`, `cache.storage-service`, `scheduler.pushers`):
  <https://docs.buildstream.build/master/using_config.html>
- NativeLink, BuildStream guide (single listener, fetch + push):
  <https://docs.nativelink.com/getting-started/other-build-systems/buildstream>
- NativeLink, Shared cache (self-hosting, storage backends, TLS, image):
  <https://docs.nativelink.com/getting-started/shared-cache>
- bazel-remote README (CAS/ActionCache/Capabilities/ByteStream; experimental
  asset Fetch subset; htpasswd/mTLS):
  <https://github.com/buchgr/bazel-remote>
- Buildbarn: <https://github.com/buildbarn> (`bb-storage`, `bb-remote-asset`)
- REAPI: <https://github.com/bazelbuild/remote-apis>
- Remote Asset API: <https://github.com/bazelbuild/remote-apis/blob/main/build/bazel/remote/asset/v1/remote_asset.proto>
