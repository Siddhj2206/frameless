# A writable remote CAS for frameless

Research note on giving frameless a **writable** remote artifact cache, so our own
elements are pushed once and pulled thereafter instead of rebuilt on every run.
It extends `docs/research/06-ci-caching-personal-account.md`, which established
that the public caches are read-only and that a personal account has no
`projectbluefin` CAS credentials.

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

## Hosting and cost

The service must be reachable from GitHub runners over TLS, and it holds real
disk (heuristic: 5–20 GB per active developer; a partial GNOME CAS is larger).

| Option | Notes | Cost |
| --- | --- | --- |
| Small VPS (Hetzner CX22 class) | 40 GB disk, filesystem backend, Caddy/nginx + Let's Encrypt for TLS | ~€4/mo |
| Oracle Cloud always-free | 4 ARM cores, 24 GB RAM, 200 GB block storage | €0 |
| Homelab | Any always-on Linux box; expose via a tunnel or a domain | €0 + electricity |
| Object storage backend (Cloudflare R2) | NativeLink/Buildbarn store blobs in R2; 10 GB free tier | €0–few |

The storage backend choice matters more than the host: filesystem is fine below
~100 GB; S3-compatible (R2/B2) scales and survives the host.

## The ROI caveat (read this before building it)

A writable CAS pays for **builds we would otherwise do from source**. With the
junction parity fixed (`docs/research/07-dakota-alpha-6.md` and the first-build
lesson), the expensive part of the graph — the freedesktop-sdk and
gnome-build-meta base, including the GNOME SDK — is **pulled from the public
caches**, not built. frameless's *own* elements are small: the runtime sources,
the os-release generator, the chunkah ownership element, and the OCI assembly.

So the writable CAS would save little on a routine build, and a lot only when:

- a junction bump lands before upstream has published that graph to the public
  caches (the element then builds from source for every run until upstream
  catches up);
- the public caches lack an element for our option set (exactly what the SDK
  rebuild was);
- we deliberately build something expensive ourselves (a custom kernel, an
  element we patch).

That is the honest ordering: **parity first, `save-always` second, a writable
CAS third** — and only if the first two still leave builds long enough to
matter.

## Recommendation

1. **Do not build it yet.** Fix the two cheap things first (junction parity;
   `actions/cache` with `save-always`), and measure. If a routine build is still
   hours after both, revisit.
2. **If it is needed**, stand up **NativeLink** (simplest, single binary,
   BuildStream integration test) on a free-tier VM or a homelab, with mTLS and a
   filesystem or R2 backend. Buildbarn's `bb-storage` + `bb-remote-asset` is the
   fallback if NativeLink disappoints.
3. **Wire it as a CI user config**, not in `project.conf`: `project.conf` stays
   pull-only and public, and CI writes a `buildstream-ci.conf` with the
   authenticated writable `artifacts.servers`/`source-caches.servers` plus
   `push: true`. The client cert/key go in repository secrets. This mirrors how
   dakota keeps its writable cache out of `project.conf`.

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
