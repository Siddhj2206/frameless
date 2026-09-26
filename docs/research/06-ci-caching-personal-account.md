# CI and caching for a BuildStream template on a personal GitHub account

Research note for the frameless BuildStream template. It answers which CI and
caching pieces the Project Bluefin BuildStream repos rely on work for a
personal-account repository without `projectbluefin` secrets, and what has to be
replaced. It builds on `docs/research/03-projectbluefin-buildstream.md` (§4-5).

## Scope and method

Primary sources:

- Local repos (read-only for this note): `/var/home/sid/Projects/dakota`,
  `/var/home/sid/Projects/fsdk-containers`, `/var/home/sid/Projects/server`.
- Public GitHub: `projectbluefin/actions` (public, Apache-2.0),
  `projectbluefin/testsuite` (public).
- BuildStream 2 docs: user configuration, project format, remote execution.
- GitHub docs: Actions limits, dependency caching, artifact attestations, OIDC,
  GHCR.
- Empirical probes from this machine on 2026-09-20: TLS handshakes and plain-HTTP
  GETs against the three cache endpoints (see §1.1).

Where a repo's prose and its executable configuration disagreed, the
configuration won.

---

## 1. The public read-only CAS endpoints

### 1.1 What is configured and what the probes show

The same two endpoints appear in all three `project.conf` files as
`artifacts:` and `source-caches:`, with no `auth:` block:

- `https://gbm.gnome.org:11003` (GNOME Build-Meta CAS)
- `https://cache.projectbluefin.io:11001` (Project Bluefin CAS)

dakota's CI also adds a third read-only cache, `https://cache.freedesktop-sdk.io:11001`
(`dakota/.github/actions/generate-bst-ci-config/action.yml`), which is the FSDK
project's own CAS. Example config: `dakota/project.conf`, `fsdk-containers/project.conf`,
`server/project.conf`; both fsdk and server annotate theirs `# Pull-only`.

Probe results (`curl -sS -m 12 -o /dev/null -w ...`):

| Endpoint | Result |
|---|---|
| `https://cache.projectbluefin.io:11001` | HTTP 404, `ssl_verify_result=0` (TLS verified against system CA, **no client cert**) |
| `https://gbm.gnome.org:11003` | HTTP 404, `ssl_verify_result=0` (**no client cert**) |
| `https://cache.freedesktop-sdk.io:11001` | HTTP 404, `ssl_verify_result=0` (**no client cert**) |
| `https://cache.projectbluefin.io:11002` | TLS alert `certificate required` — **mTLS is mandatory** |

A plain-HTTP GET to a gRPC server returning 404 is expected; the meaningful
result is that the TLS handshake completes with the OS CA store and no client
certificate. This matches BuildStream's documented model:

> "Remote cache services may allow downloading artifacts and sources without
> authentication, in which case only server-cert is required for secure access
> (or no attributes at all if the CA store from the OS can be used). However,
> remote cache services should normally not allow uploading artifacts or sources
> without authentication."
> — <https://docs.buildstream.build/master/using_config.html>

So all three read-only endpoints are **open to anyone**, and a personal repo can
pull from them with no secrets.

### 1.2 What a personal repo actually gets

These are caches shared by the upstream dependency projects. Because BuildStream
namespaces artifacts by project name, frameless inherits cache hits for
everything it pulls through its junctions (`freedesktop-sdk.bst`,
`gnome-build-meta.bst`), but **not** for its own elements — those cache keys are
new and are absent, so they rebuild locally. That is still a large win: the FSDK
and GBM base is the expensive part.

The public caches are read-only for a caller by two mechanisms: no `push:` in the
project-recommended stanza, and no credentials to push with. BuildStream project
recommendations are "the lowest priority configuration" and cannot grant write
access on their own:

> "To provide write access to downstream users, it is recommended that the
> required private keys such as the client-key be provided to users out of band,
> and require that users configure write access separately in their own user
> configuration."
> — <https://docs.buildstream.build/master/format_project.html>

---

## 2. The writable cache CI adds, and what to substitute

### 2.1 What the Project Bluefin CI uses

dakota's local composite action writes a user config that adds an authenticated
writable CAS plus remote execution, at `cache.projectbluefin.io:11002`:

- `artifacts.servers` / `source-caches.servers`: `push: true`, `auth.client-cert`
  and `auth.client-key` from `CASD_CLIENT_CERT` (repo **variable**) and
  `CASD_CLIENT_KEY` (**secret**).
- `storage-service` and `remote-execution.*` point at the same endpoint with the
  same mTLS identity.
- Read-only fallbacks: `gbm.gnome.org:11003`, `cache.freedesktop-sdk.io:11001`.
- `cache.cache-buildtrees: never`.
- If remote execution is requested and the client credentials are missing, the
  action **fails closed**.

Files: `dakota/.github/actions/generate-bst-ci-config/action.yml`,
`dakota/.github/workflows/build.yml` (lines 155-165),
`dakota/.github/workflows/publish.yml` (lines 154-162).

The `:11002` mTLS certificate is org-provisioned. A personal account cannot
obtain it, and the probe in §1.1 confirms the endpoint rejects a client without
one. **This is the single hard blocker and it must be replaced.**

### 2.2 Substitutes

**(a) GitHub Actions cache.** Cache `~/.cache/buildstream` with `actions/cache`
(the bst2 Justfile mounts `${HOME}/.cache/buildstream` into the container — see
`fsdk-containers/Justfile` and `server/Justfile`). Constraints, from
<https://docs.github.com/en/actions/reference/workflows-and-actions/dependency-caching>:

- Default 10 GB per repository on Free/Pro; 7-day eviction of untouched entries.
- Entries are immutable, keyed by string; a new key creates a new entry.
- User-owned repositories can raise the limit up to 10 TB with a payment method.

Verdict: fine for a template that builds a modest set of elements, not for a
full desktop OS image. It is a directory cache, not a CAS protocol — BuildStream
does not natively speak the Actions cache API.

**(b) Self-hosted REAPI cache.** BuildStream talks to any
[REAPI](https://github.com/bazelbuild/remote-apis) storage/action-cache backend.
BuildStream's docs name BuildGrid, BuildBarn and Buildfarm
(<https://docs.buildstream.build/master/using_configuring_remote_execution.html>),
and NativeLink documents a BuildStream setup with `artifacts.servers` +
`remote-execution` on one listener
(<https://docs.nativelink.com/getting-started/other-build-systems/buildstream>).
A small VPS or homelab service with a bearer `access-token` (or mTLS) gives
frameless a private writable cache without org credentials. BuildStream config
supports `auth.access-token` for exactly this:
<https://docs.buildstream.build/master/using_config.html>.

Do **not** stand up an anonymous, publicly writable CAS: BuildStream's own docs
say uploads "should normally not allow" being unauthenticated, and an open
writable CAS is a cache-poisoning target.

**(c) No shared writable cache.** The `server` repo's model: `project.conf` is
pull-only and CI builds locally in the bst2 container
(`server/.github/workflows/build.yml`, lines 85-121). Cost: frameless's own
elements rebuild every run; everything inherited from FSDK/GBM comes from the
public caches.

---

## 3. Are the `projectbluefin/actions` pieces reusable?

The repository is **public** (`projectbluefin/actions`, `"visibility":"public"`,
Apache-2.0, default branch `main`, tags `v1`, `v1.0.0`, `v1.1.0`). Reusable
workflows in a public repo can be called from any repository with
`{owner}/{repo}/.github/workflows/{file}@{ref}`, and composite actions with
`uses: projectbluefin/actions/<path>@v1`
(<https://docs.github.com/en/actions/how-tos/reuse-automations/reuse-workflows>).

| Piece | Public? | Works on a personal repo? | Org coupling to override / replace |
|---|---|---|---|
| `bootc-build/setup-runner@v1` | yes | **Yes, unchanged** | None. Pure public actions + `actions/cache`; Ubuntu-24.04-specific. Not BuildStream-aware. |
| `bootc-build/sign-and-publish@v1` | yes | Yes, with overrides | Default `certificate-identity-regexp` is anchored to `projectbluefin` — the action's own docs say callers "must override this with their own org prefix". Keyless needs only `id-token: write`. `push-attestation`/`generate-sbom` use `actions/attest` (see §5). |
| `.github/workflows/reusable-execute-release.yml@v1` | yes | Yes, with overrides | `registry` defaults to `ghcr.io/projectbluefin` but is an input. `release-gate` calls `projectbluefin/testsuite` (public) — pass `run_release_gate: false`. Optional Discord step reads `secrets.DISCORD_RELEASES_WEBHOOK` but is skipped when `tag_name` is empty. `$/`-local actions resolve inside `projectbluefin/actions`, not the caller. |
| `.github/workflows/reusable-release.yml@v1` | yes | Yes | Generic inputs (`image`, `project_name`, `cert_identity_regexp`, `sbom_artifact`). Sets `environment: production` on the image-release job. Uses `$/bootc-build/create-release`. |
| `generate-bst-ci-config` | **not in the shared repo** | — | This is a **dakota-local** composite action (`dakota/.github/actions/generate-bst-ci-config/action.yml`). It exists specifically to write the org mTLS `cache.projectbluefin.io:11002` + remote-execution config and fails closed without `CASD_CLIENT_*`. There is nothing to reuse; frameless must write its own. |
| `.github/workflows/reusable-build.yml@v1` | yes | n/a | Targets the Fedora bootc/RPM flow, not BuildStream. Not applicable. |

Net: the shared actions are genuinely public and the useful ones survive the
move to a personal account with input overrides. The **cache and remote-execution
configuration is not shared at all** — it is org-local and is exactly the piece
that does not transfer.

---

## 4. Remote execution

- dakota: `cache.projectbluefin.io:11002` with mTLS. Unavailable.
- fsdk: the "ghost cluster" BuildBarn grid, reached by `kubectl port-forward`
  from the developer's kubeconfig (`fsdk-containers/Justfile`, lines 35-101;
  `frontend.buildbarn.svc:8980`). CI always builds locally
  (`GITHUB_ACTIONS=true` forces `BST_LOCAL`). Private cluster, unavailable.
- server: builds locally in the pinned bst2 container; a documented
  `cluster-build` Argo path exists for heavy builds. This is the closest model
  to what a personal repo can do without new infrastructure.

A personal repo should **build locally in the bst2 container**. BuildStream
remote execution needs a REAPI backend that implements platform properties and
treats the input root as the filesystem root
(<https://docs.buildstream.build/master/using_configuring_remote_execution.html>);
GitHub-hosted runners cap jobs at 6 hours
(<https://docs.github.com/en/actions/reference/limits>). If a frameless build
ever exceeds that, either lean harder on the public read-only caches or
self-host BuildGrid/BuildBarn/NativeLink. Remote execution is an optimization,
not a requirement — `server` ships without it.

---

## 5. Signing, SBOM, and attestation on a personal repo

**Keyless cosign works on any repository.** GitHub's OIDC provider issues a
per-job token whenever `id-token: write` is granted; the token's
`job_workflow_ref` / `sub` claims identify
`<owner>/<repo>/.github/workflows/<workflow>@<ref>`
(<https://docs.github.com/en/actions/concepts/security/openid-connect>). That
identity is what verifiers pin with `--certificate-identity-regexp` and the
issuer `https://token.actions.githubusercontent.com`. No org secret is involved.

Practical overrides for frameless:

- Set `certificate-identity-regexp` to the frameless repo's workflow, e.g.
  `^https://github\.com/Siddhj2206/frameless/\.github/workflows/<publish>\.yml@refs/heads/(main|stable)$`.
- Keep `new-bundle-format: false` for podman/bootc compatibility (the action's
  comment explains that containers/image resolves signatures only via the legacy
  `sha256-<digest>.sig` tag).

**GHCR on a personal account works.** `GITHUB_TOKEN` with `packages: write` can
publish packages associated with the workflow repository; new packages default to
private; per-layer limit 10 GB
(<https://docs.github.com/en/packages/working-with-a-github-packages-registry/working-with-the-container-registry>).

**Attestations have a visibility catch.**

- Public personal repo: `actions/attest` and `actions/attest-build-provenance`
  use the Sigstore Public Good Instance → SLSA v1.0 Build Level 2 for free
  (<https://docs.github.com/en/actions/concepts/security/artifact-attestations>).
- Private repo: "To use artifact attestations in private or internal
  repositories, you must be on a GitHub Enterprise Cloud plan."
  (<https://docs.github.com/en/actions/how-tos/secure-your-work/use-artifact-attestations/use-artifact-attestations>).

Portable alternative that needs only GHCR + `id-token: write`: attach the SBOM
with `oras` (artifact type `application/vnd.spdx+json`) and sign it with keyless
cosign. dakota's `publish-sbom` job does exactly this, and fsdk's
`oci-images.yml` (lines 206-238) does attach + sign + attest. On a private repo,
drop the GitHub attestation steps and keep the oras/cosign path.

---

## 6. Recommendation for frameless

1. **Caching.** Keep `project.conf` pull-only against the three public read-only
   caches (`gbm.gnome.org:11003`, `cache.projectbluefin.io:11001`,
   `cache.freedesktop-sdk.io:11001`), no `auth:`. Start with **no shared writable
   cache**: build locally in the pinned bst2 container, as `server` does. Add
   `actions/cache` on `~/.cache/buildstream` as the cheap warm-cache layer, keyed
   to the element graph and capped at the 10 GB default. Only if builds outgrow
   that, add a self-hosted REAPI cache (NativeLink/BuildGrid/BuildBarn) with a
   bearer token — never an anonymous writable public CAS.
2. **CI.** Reuse `projectbluefin/actions/bootc-build/setup-runner@v1` as-is. Do
   **not** copy dakota's `generate-bst-ci-config`; write a local config generator
   that references only the public caches (or nothing, since `project.conf`
   already covers pulls).
3. **Remote execution.** Default to local. Add RE only if a self-hosted cluster
   exists; a 6-hour runner cap is the trigger to revisit.
4. **Signing.** Keyless OIDC cosign on GHCR, with
   `certificate-identity-regexp` re-anchored to `Siddhj2206/frameless` and
   `new-bundle-format: false`. Use `sign-and-publish@v1` with those overrides, or
   inline cosign + oras as fsdk does.
5. **SBOM/attestation.** If frameless is public, `actions/attest` with
   `sbom-path` plus `attest-build-provenance` gives SLSA L2 for free. If it is
   private, skip GitHub attestations (GHEC required) and attach + sign the SBOM
   with oras/cosign instead.
6. **Promotion.** `reusable-execute-release@v1` is callable with
   `registry: ghcr.io/Siddhj2206`, `run_release_gate: false`, and no `tag_name`;
   `reusable-release@v1` is generic. Treat both as optional — fsdk's self-contained
   manifest/sign/publish lane is a simpler reference for a template.

---

## Sources

Local files:

- `dakota/project.conf`; `fsdk-containers/project.conf`; `server/project.conf`.
- `dakota/.github/actions/generate-bst-ci-config/action.yml`.
- `dakota/.github/workflows/build.yml`, `publish.yml`, `execute-release.yml`.
- `fsdk-containers/.github/workflows/oci-images.yml`; `fsdk-containers/Justfile`.
- `server/.github/workflows/build.yml`; `server/Justfile`.
- `docs/research/03-projectbluefin-buildstream.md` (§4-5).

External:

- BuildStream user configuration (auth, cache servers, remote execution):
  <https://docs.buildstream.build/master/using_config.html>
- BuildStream project format (artifact/source-cache recommendations):
  <https://docs.buildstream.build/master/format_project.html>
- BuildStream remote execution servers:
  <https://docs.buildstream.build/master/using_configuring_remote_execution.html>
- NativeLink BuildStream guide:
  <https://docs.nativelink.com/getting-started/other-build-systems/buildstream>
- REAPI: <https://github.com/bazelbuild/remote-apis>
- `projectbluefin/actions` repo and contents:
  <https://github.com/projectbluefin/actions>
  (`README.md`, `bootc-build/setup-runner/action.yml`,
  `bootc-build/sign-and-publish/action.yml`,
  `.github/workflows/reusable-execute-release.yml`,
  `.github/workflows/reusable-release.yml`)
- `projectbluefin/testsuite`: <https://github.com/projectbluefin/testsuite>
- GitHub Actions limits (runner limits, cache storage):
  <https://docs.github.com/en/actions/reference/limits>
- GitHub dependency caching (10 GB/repo default, 7-day eviction, cache-mode):
  <https://docs.github.com/en/actions/reference/workflows-and-actions/dependency-caching>
- GitHub reusable workflows (public cross-repo calling):
  <https://docs.github.com/en/actions/how-tos/reuse-automations/reuse-workflows>
- GitHub artifact attestations (concepts):
  <https://docs.github.com/en/actions/concepts/security/artifact-attestations>
- GitHub artifact attestations (private repo requires GHEC):
  <https://docs.github.com/en/actions/how-tos/secure-your-work/use-artifact-attestations/use-artifact-attestations>
- GitHub OIDC:
  <https://docs.github.com/en/actions/concepts/security/openid-connect>
- GHCR on personal accounts:
  <https://docs.github.com/en/packages/working-with-a-github-packages-registry/working-with-the-container-registry>

Endpoint probes were run from this machine on 2026-09-20 with
`curl -sS -m 12 -o /dev/null -w 'http=%{http_code} tls=%{ssl_verify_result}\n'`.
No files in the frameless repository were modified.
