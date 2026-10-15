# Running `bst` locally: the Project Bluefin `bst2` container pattern

Research question: **What is the exact local invocation to run `bst`?** `bst` is
not installed on this machine. All three Project Bluefin BuildStream repos run it
inside the freedesktop-sdk `bst2` container through a `just bst` wrapper.

Sources read (primary: the Justfiles and their docs; nothing here is inferred
from a secondary write-up):

- `/var/home/sid/Projects/dakota` — `Justfile:20,43-80`, `docs/build.md`,
  `.agents/skills/dakota-buildstream/SKILL.md`, `.github/workflows/*`
- `/var/home/sid/Projects/fsdk-containers` — `Justfile:16-114`, `docs/skills/buildstream.md`,
  `docs/skills/bump-fsdk-version.md`, `docs/skills/remote-execution.md`, `README.md`
- `/var/home/sid/Projects/server` — `Justfile:6-37`, `AGENTS.md`, `README.md`
- Upstream BuildStream 2 tutorial (`docs.buildstream.build/2.5/tutorial/first-project.html`)
- Registry checks via `skopeo inspect` and `podman pull`/`podman inspect`

Verified on this machine: `podman 5.8.4`, rootless podman works, `/dev/fuse`
present, `x86_64`. The pinned image was pulled and the upstream hello-world was
built, shown and checked out through it (see section 4).

---

## 1. The exact `podman run` command

All three repos wrap the same invocation. The canonical shape (dakota, the parent
project) is:

```bash
podman run --rm \
    --privileged \
    --device /dev/fuse \
    --network=host \
    ${BST_PODMAN_EXTRA_ARGS:-} \
    -v "$(pwd):/src:rw" \
    -v "$HOME/.cache/buildstream:/root/.cache/buildstream:rw" \
    -w /src \
    "registry.gitlab.com/freedesktop-sdk/infrastructure/freedesktop-sdk-docker-images/bst2" \
    bash -c 'bst --colors "$@"' -- ${EFFECTIVE_BST_FLAGS} build oci/bluefin.bst
```

Source: `dakota/Justfile:71-80`. Notes:

- `--privileged` and `--device /dev/fuse` give the container the capabilities and
  FUSE device BuildStream's sandbox needs. Both are present in all three repos.
- `--network=host` lets the container reach host services — in fsdk-containers
  and server this is what makes the `kubectl port-forward` on `127.0.0.1:18980`
  reachable for remote execution.
- The project directory is mounted read-write at `/src`, and the host BuildStream
  cache is mounted at `/root/.cache/buildstream` so artifacts persist between
  runs (the container runs as root, so rootless podman maps that to your user).
- `-w /src` sets the working directory; the repo root is where `project.conf`
  lives.
- `bash -c 'bst --colors "$@"' -- <flags> <args>` runs `bst` with the flags and
  the user's arguments. `--colors` restores colour (the CLI strips it under a
  non-tty). `${ARGS}` in the Justfile is word-split by `just`, which is why
  spaces in values (e.g. `--format`) are discouraged (`fsdk-containers/docs/skills/buildstream.md:100-101`).

### Per-repo differences

| | dakota | fsdk-containers | server |
|---|---|---|---|
| Image default | bare ref (→`:latest`) | pinned `:64eb0b49…` | pinned `:64eb0b49…` |
| Auto-`sudo` prefix | no | yes (`sudo_cmd`) | yes (`sudo_cmd`) |
| Default flags | `-o x86_64_v3 false --no-interactive -o gaming <bool>` | `--no-interactive` + RE `--config` | `--no-interactive --error-lines 500` |
| Extra podman args | `BST_PODMAN_EXTRA_ARGS` | none | none |
| Alt runner hook | `BST_RUNNER` (used by tests) | — | — |
| Version include | — | regenerates `include/fsdk-version.yml` | — |
| Remote execution | no (local) | yes by default, `BST_LOCAL=1` opts out | no (local) |

- **dakota** (`Justfile:43-80`) defaults to baseline `x86_64_v3 false` so local
  runs match CI and can reuse gnome-build-meta / freedesktop-sdk artifacts, adds
  `-o gaming <bool>`, and injects `--no-interactive`. It honours `BST_FLAGS`
  (append) and `BST_FLAGS_OVERRIDE` (replace), and `BST_RUNNER` for isolated
  tests. `BST_PODMAN_EXTRA_ARGS` is an escape hatch (CI mounts a hotfixed module).
- **fsdk-containers** (`Justfile:46-114`) regenerates `include/fsdk-version.yml`
  before every run (section 2), and by default injects a remote-execution
  `--config /src/.bst-re.conf` that points at `127.0.0.1:18980`; it hard-fails if
  the BuildBarn cluster is unreachable. `BST_LOCAL=1` forces local execution.
  `sudo_cmd := if podman info works then "" else "sudo"` (`Justfile:23`).
- **server** (`Justfile:22-37`) is the simplest: `--privileged --device /dev/fuse
  --network=host`, no RE config, `--no-interactive --error-lines 500`. It
  exports `CONTAINERS_CONF=/dev/null` and `CONTAINERS_CONF_OVERRIDE=/dev/null`
  before the podman call (`Justfile:25-26`), i.e. it tells podman to ignore the
  host's container config.

If you copy one as a base for frameless, dakota's is the parent project and the
one AGENTS.md points at.

---

## 2. Image reference and digest (verified)

Pinned image (`fsdk-containers/Justfile:16`, `server/Justfile:7`):

```
registry.gitlab.com/freedesktop-sdk/infrastructure/freedesktop-sdk-docker-images/bst2:64eb0b4930d57a92710822898fb73af6cc1ae35d
```

Verified with `skopeo` and a real `podman pull`:

- Tag is an **OCI/Docker manifest list**:
  `application/vnd.docker.distribution.manifest.list.v2+json`, digest
  `sha256:2ca3b449b594e9284bd60f436a4efad1365116b7d3d7129fd08b7a4f459d3561`.
- Platform manifests: amd64 `sha256:9bb26c24ad60ec0c0b45ab89fce1320e5fb81fb89b31668e369b3bc8f721f336`,
  arm64 `sha256:0ae910a4…`, ppc64le `sha256:63f774f4…`, riscv64 `sha256:6ea4034a…`.
- Config: `Architecture: amd64`, `Os: linux`, `Cmd: ["/bin/bash"]`, no env, no labels.
- Two layers (~22.6 MB + ~449.4 MB).
- `podman inspect` on this x86_64 host: image ID
  `45e9189f5a1191881721b3e2d9240dc8e19a683d9fecbcbe6901eeed8e06f229`,
  RepoDigests `…bst2@sha256:2ca3b449…` and `…bst2@sha256:9bb26c24…`.
- Container ships `bst` at `/usr/sbin/bst`, **version 2.7.0** (verified inside
  the container). Project `min-version: 2.5` in all three repos, so the image is
  ahead of the required minimum.

The floating `:latest` tag resolves to a *different* digest
(`sha256:b090811a617cb4c11c8ab9b08aa272a6b90c58cb289193f178ea5ca4d3ced681`),
which is why fsdk-containers/server pin by SHA and dakota's comment says leaving
it unset uses "the upstream image default instead of a repo-local digest pin"
(`dakota/Justfile:18-20`). dakota's CI does exactly that: it pulls the bare
ref (`dakota/.github/workflows/track-bst-sources.yml:34,180`).

Not every tag in that repository is multi-arch — the registry listing includes
single-arch `-amd64` suffixes. The pinned `:64eb0b49…` tag is multi-arch, so it
works on x86_64 and aarch64.

---

## 3. The single version source: junction `ref:` → `fsdk_version`

The FSDK release is never written down twice. It is parsed out of the `ref:` line
of `elements/freedesktop-sdk.bst`, the junction pin, and that parse is the only
source.

### fsdk-containers (the fullest form)

`Justfile:25-29`:

```just
export fsdk_version := `grep -E '^\s*ref:' elements/freedesktop-sdk.bst | head -1 \
    | sed -E 's/.*freedesktop-sdk-//; s/-[0-9]+-g[0-9a-f]+$//'`
export fsdk_ref := `grep -E '^\s*ref:' elements/freedesktop-sdk.bst | head -1 \
    | sed -E 's/^\s*ref:\s*//'`
```

For the current ref `freedesktop-sdk-26.08.0-0-gdb97cce32cecadc7a3e98f06d557ebfa6ba9ad46`
this yields `26.08.0` (verified). The `-0-g<sha>` git-describe suffix is stripped
so pre-release forms like `26.08beta.1` survive.

The `just bst` wrapper then **regenerates `include/fsdk-version.yml` on every
invocation** (`Justfile:56-58`):

```just
cat > include/fsdk-version.yml <<'EOF'
fsdk-version: "{{fsdk_version}}"
EOF
```

The file is git-ignored and never hand-edited
(`docs/skills/bump-fsdk-version.md:38-42`, `docs/skills/buildstream.md:72-75`).
Elements pull it in with `(@): include/fsdk-version.yml`
(e.g. `elements/oci/base.bst:19`, `elements/podman-vm/podman-vm-efi.bst:68`) and
substitute `%{fsdk-version}` into the OCI image reference name
(`'org.opencontainers.image.ref.name': 'ghcr.io/projectbluefin/base:%{fsdk-version}'`)
and into VM artifact filenames (`donate-clanker-vm-%{fsdk-version}-%{arch}.raw`).
`fsdk_version` also feeds `just tags` (`Justfile:123-132`), which emits the minor
line (`26.08`) and the point release (`26.08.0`), deliberately not `latest`, plus
the `sbom`/`sboms` recipes that invoke the container directly and must regenerate
the same include (`Justfile:922-924, 964-965`).

### server

`Justfile:12-16`:

```just
export fsdk_version := `grep -oE 'freedesktop-sdk-[0-9]+\.[0-9]+\.[0-9]+' elements/freedesktop-sdk.bst \
    | head -1 | sed 's/freedesktop-sdk-//'`
export fsdk_ref := `grep -E '^\s*ref:' elements/freedesktop-sdk.bst | head -1 \
    | sed -E 's/^\s*ref:\s*//'`
```

Same junction ref, same current value `26.08.0` (verified). It feeds
`just version` (`Justfile:40-42`), `just tags` (latest/minor/point,
`Justfile:46-51`), and the per-version VM state directory
(`Justfile:380`). It does **not** generate an `include/fsdk-version.yml`; server's
elements use `%{release-version}` and `%{k0s-version}` instead. Note the
`grep -oE '…[0-9]+\.[0-9]+\.[0-9]+'` form only matches numeric point releases, so
it would not match a `26.08beta.N` ref — the fsdk-containers `sed` form is the
more robust one.

### dakota

Dakota has **no** `fsdk_version` derivation in its Justfile. `grep -rn fsdk`
across its Justfile, `project.conf`, docs, workflows and scripts returns nothing.
Dakota's junction pin is consumed by BuildStream directly, and its own image
version comes from `BUILD_IMAGE_TAG` (`Justfile:8`). Its version-derivation logic
that *does* exist is for the gnome-build-meta junction used by the patch-sync
check (`Justfile:123-128`), not for the FSDK release. So "the single version
source trick" is an fsdk-containers/server pattern; if frameless needs a
version-derived tag or label, fsdk-containers' regenerate-the-include approach is
the one to copy.

---

## 4. Common operations through the wrapper

`just bst <args>` forwards `<args>` straight to `bst` inside the container. The
three repos document and use the same set (`fsdk-containers/docs/skills/buildstream.md:86-98`,
`dakota/docs/build.md:45-52`):

| Operation | Command |
|---|---|
| Resolve / inspect the graph | `just bst show oci/bluefin.bst` / `just bst show --deps all oci/bluefin.bst` |
| Build one element | `just bst build oci/bluefin.bst` |
| Build ignoring deps (CI) | `just bst build --deps none oci/bluefin.bst` |
| Enter the sandbox | `just bst shell --build bluefin/tailscale.bst` |
| Re-resolve a source ref | `just bst source track freedesktop-sdk.bst` |
| Check out an artifact | `just bst artifact checkout oci/bluefin.bst --directory /src/.build-out` |
| List built contents | `just bst artifact list-contents <element>` |
| Read a build log | `just bst artifact log <element>` |
| Delete a cached failure | `just bst artifact delete <element>` |

Concrete call sites: `dakota/Justfile:251` (`just bst build "$ELEMENT"`),
`dakota/Justfile:286` (`just bst artifact checkout "$ELEMENT" --directory /src/.build-out`),
`dakota/Justfile:101-102` (`just bst show --deps all …`), `server/Justfile:58-60`
(same), `server/Justfile:96` (`just bst artifact checkout oci/bluefin-server-ddi.bst --directory /src/dist/ddi`),
`fsdk-containers/Justfile` `validate` via `just bst show`, and the nightly track
workflows run `just bst source track <element>`
(e.g. `fsdk-containers/docs/skills/bump-fsdk-version.md:161`,
`dakota/.github/workflows/track-bst-sources.yml:185`).

`artifact checkout` requires an empty destination, so repos `rm -rf` the target
first (`server/Justfile:115-123`).

## 4b. Upstream "first project" hello-world through the same container

The container ships the core `import` and `local` plugins, so upstream's
first-project tutorial works with no junction and no remote cache. I ran it
end-to-end through the exact wrapper command; it built artifact
`8b3d535225335b4842b5d6b98ee6fdffc7340e190f33b79a2043f5c31e43fbde` (the same
hash as the upstream docs), reported `cached`, and produced `here/hello.world`.
The container used **bst 2.7.0**.

Copy-pasteable, self-contained:

```bash
IMAGE=registry.gitlab.com/freedesktop-sdk/infrastructure/freedesktop-sdk-docker-images/bst2:64eb0b4930d57a92710822898fb73af6cc1ae35d
mkdir -p ~/bst-hello/elements && cd ~/bst-hello

cat > project.conf <<'EOF'
name: first-project
min-version: 2.5
element-path: elements
EOF

touch hello.world

cat > elements/hello.bst <<'EOF'
kind: import
sources:
- kind: local
  path: hello.world
config:
  target: /
EOF

# build / show / checkout, exactly as the upstream tutorial does
podman run --rm --privileged --device /dev/fuse --network=host \
  -v "$PWD:/src:rw" \
  -v "$HOME/.cache/buildstream:/root/.cache/buildstream:rw" \
  -w /src \
  "$IMAGE" \
  bash -c 'set -e; bst --colors --no-interactive build hello.bst; \
           bst --colors --no-interactive show hello.bst; \
           bst --colors --no-interactive artifact checkout --directory here hello.bst; \
           ls -la here'
```

You can also let BuildStream create the skeleton itself inside the container
(`bst init --project-name first-project`), which is the tutorial's own first
step; the three files above are what it produces.

A frameless-shaped equivalent (once frameless has a Justfile with the wrapper)
would be `just bst build hello.bst`, `just bst show hello.bst`,
`just bst artifact checkout --directory here hello.bst`.

---

## 5. Gotchas

1. **Rootless vs rootful podman must not be mixed.** fsdk-containers and server
   auto-detect: `sudo_cmd := if podman info works then "" else "sudo"`
   (`fsdk-containers/Justfile:23`, `server/Justfile:10`). Mixing plain and
   `sudo podman` in the same cache leaves root-owned files under
   `~/.cache/buildstream` that the other mode cannot write; the ci-tooling skill
   says pick one and stay consistent (`fsdk-containers/docs/skills/ci-tooling/SKILL.md:58-69`).
   Rootless is sufficient on this machine (verified).
2. **`/dev/fuse` and `--privileged` are load-bearing.** Without them BuildStream
   cannot set up its sandbox. Both are in every repo's wrapper. The VM/bwrap
   tests in fsdk-containers additionally need `--cap-add SYS_ADMIN` for nested
   `bwrap` (`Justfile:521-534`) — that is for the lab-runner image test, not for
   `bst` itself.
3. **SELinux labels.** None of the three wrappers pass `:z`/`:Z` on the `/src` or
   cache mounts. On an SELinux-enforcing host that denies the container access to
   a `user_home_t` path, the mount fails with permission-denied; the fix is to
   relabel (`:z`) or run on a host where the context is unconfined. This machine
   is `unconfined_u:…` and the mounts worked unlabelled, so the repos' omission
   is deliberate/incidental but not portable.
4. **`--network=host` is required for remote execution.** fsdk-containers starts
   `kubectl port-forward -n buildbarn svc/frontend 18980:8980` on the host and
   passes a config whose URLs are `grpc://127.0.0.1:18980`; only host networking
   makes that reachable from the container (`docs/skills/remote-execution.md:48-69`).
   It also means concurrent `just bst` runs fight over port 18980
   (`remote-execution.md:103`).
5. **fsdk-containers fails closed on remote execution.** If the BuildBarn
   frontend is unreachable it errors out rather than falling back to local
   (`Justfile:63-69`, `docs/skills/remote-execution.md:37-46`). For a newcomer or
   a machine with no kubeconfig, use `BST_LOCAL=1 just bst …`. `BST_LOCAL=1` is
   documented as a diagnostic/opt-out, not an operating model.
6. **The cache mount is the whole point.** `-v "$HOME/.cache/buildstream:/root/.cache/buildstream:rw"`
   is what makes repeat invocations fast; without it every run rebuilds. With
   rootless podman this lands under your user's home, so `mkdir -p` it first
   (all three wrappers do, `dakota/Justfile:49`, `fsdk-containers/Justfile:49`,
   `server/Justfile:27`).
7. **The container is `bst` 2.7.0; the pinned tag matters.** Different tags can
   ship different BuildStream versions and different plugin sets. fsdk-containers
   and server pin the SHA; dakota defaults to `:latest` and its CI overrides
   `BST2_IMAGE` to the bare ref.
8. **Argument word-splitting.** `just` splits `{{ARGS}}` on whitespace, so
   `--format "%{name} %{state}"` breaks; use a separator without spaces
   (`fsdk-containers/docs/skills/buildstream.md:100-101`).
9. **`CONTAINERS_CONF=/dev/null`** (server only) neutralises the host's
   `containers.conf` for the podman call — useful when a host config injects
   options the `bst2` image disagrees with (`server/Justfile:25-26`).

---

## 6. Recommendation for frameless

Adopt the dakota wrapper shape (`--rm --privileged --device /dev/fuse
--network=host`, project at `/src:rw`, cache at `/root/.cache/buildstream:rw`,
`-w /src`, `bash -c 'bst --colors "$@"' -- <flags> <args>`), pin the bst2 image
by SHA like fsdk-containers/server do, and if frameless needs a version-derived
tag or `%{fsdk-version}` variable, copy fsdk-containers' regenerate
`include/fsdk-version.yml` trick. Keep `sudo_cmd` auto-detection out unless
rootful podman is actually needed; rootless works.

---

## 7. Update (2026-09-20): the pinned digest carried BuildStream 2.7

The `:64eb0b49…` digest verified in section 2 carries **BuildStream 2.7.0**.
That is fine for dakota, fsdk-containers, and server because all three declare
`min-version: 2.5`. It is *not* fine for frameless, which declares
`min-version: 2.8`: every `just bst` invocation failed at project load with

```
Error loading project: project.conf [line 25 column 13]: Version mismatch
    Project requires at least BuildStream 2.8, but BuildStream 2.7 is installed.
```

The floating `:latest` tag now carries **2.8.0** (manifest-list digest
`sha256:b090811a617cb4c11c8ab9b08aa272a6b90c58cb289193f178ea5ca4d3ced681`), so
`just bst` pins that digest instead. The lesson: `min-version` is a floor the
*runner* must clear, so the runner digest and `min-version` are one decision —
bump them together. See `elements/core/sandbox-tools.bst` for the sibling
finding that FSDK 26.08's `runtime-minimal` no longer carries a shell.
