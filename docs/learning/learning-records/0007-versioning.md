# Versioning from the junction ref

The image version has one source: the pinned freedesktop-sdk junction ref in
`elements/freedesktop-sdk.bst`. A `just` expression parses it to `fsdk_version`
(`freedesktop-sdk-26.08.1-0-gb02b59f…` → `26.08.1`), and `just bst` writes it to
a gitignored `include/fsdk-version.yml` that elements read as `%{fsdk-version}`.
os-release's `VERSION`/`VERSION_ID`/`IMAGE_VERSION` and the OCI
`org.opencontainers.image.version` label all come from it.

The pattern is fsdk-containers': regenerate the include on every `bst`
invocation so elements never re-parse the ref, and gitignore it. `just tags`
prints the minor stream (`26.08`) and the exact release (`26.08.1`) for CI.

Why this and not a date: dakota bakes `latest` and lets the OCI tag carry the
meaning, because promotion retags the same digest. A template benefits from an
in-image version that traces to the base it was built on, and the junction ref is
the only thing that actually moves the base.

The two-branch release model and keyless signing were already implemented by the
inherited workflows (`promote-main-to-stable`, `execute-release`,
`sync-stable-to-main`) and are unchanged; only the build they promote changes
in #22.
