#!/usr/bin/env bash
# Move the BuildStream cache between CI runs as a GHCR OCI artifact.
#
# Why not actions/cache: the cache is ~14 GB and GitHub's per-repo cache limit
# is 10 GB, so the entry was evicted and every run started cold. GHCR container
# image storage and bandwidth are free, and the registry has no such ceiling.
#
# Why the whole cache rather than only our own artifacts: selecting the delta
# needs a reachability walk over the CAS, because BuildStream has no CAS delete
# and an artifact ref is only a tiny pointer. That is a worthwhile optimisation
# (see docs/research/10-remote-availability-cache-pruning.md) but a full
# snapshot is simple and correct, and GHCR does not charge for it.
#
# The cache is an optimisation: a failure here must never fail the build. Pull
# treats every problem as "start cold"; push reports the error but the workflow
# carries `continue-on-error`, so the image still publishes.
#
# Retry the pull: the artifact is ~12 GB, GHCR serves blobs through a CDN, and a
# failure part-way through costs a *cold* build — 70 minutes on frameless, and
# far more for a graph that rebuilds a desktop stack. A 2026-09-25 run lost the
# cache to one transient pull failure and re-pulled 771 elements as a result.
#
# Environment:
#   BST_CACHE_REF  required. e.g. ghcr.io/owner/repo-cache
#   BST_CACHE_KEY  optional. A graph-derived key; when set, a second tag is
#                  written so a cache matching the current graph can be
#                  preferred over the rolling one.
#   BST_CACHE_DIR  optional. Defaults to ~/.cache/buildstream.
#   GH_TOKEN, GITHUB_ACTOR  optional. Used to log in when both are set.

set -euo pipefail

MEDIA_TYPE="application/vnd.buildstream.cas.tar.zst"
PULL_ATTEMPTS=3
CACHE_DIR="${BST_CACHE_DIR:-${HOME}/.cache/buildstream}"
REF="${BST_CACHE_REF:-}"
KEY="${BST_CACHE_KEY:-}"

# Set by push() and read by the EXIT trap; must outlive the function.
tmp=""

usage() {
    echo "usage: $(basename "$0") {pull|push}" >&2
    exit 2
}

cleanup() {
    if [ -n "${tmp}" ]; then
        rm -rf "${tmp}"
    fi
}
trap cleanup EXIT

require_ref() {
    if [ -z "${REF}" ]; then
        echo "BST_CACHE_REF is not set (e.g. ghcr.io/owner/repo-cache)" >&2
        exit 1
    fi
}

require_tools() {
    local tool
    for tool in "$@"; do
        if ! command -v "${tool}" >/dev/null 2>&1; then
            echo "${tool} is required but not on PATH" >&2
            exit 1
        fi
    done
}

login() {
    if [ -n "${GH_TOKEN:-}" ] && [ -n "${GITHUB_ACTOR:-}" ]; then
        printf '%s' "${GH_TOKEN}" | oras login ghcr.io -u "${GITHUB_ACTOR}" --password-stdin >/dev/null
    fi
}

# Try the graph key first, then the rolling tag: the rolling one may be from a
# different graph, but BuildStream still uses whatever artifacts match. Every
# failure is a cold start rather than an error — see the header.
pull() {
    require_ref
    require_tools oras tar zstd
    login

    local tag attempt reason
    for tag in ${KEY:+"${KEY}"} latest; do
        for ((attempt = 1; attempt <= PULL_ATTEMPTS; attempt++)); do
            echo "==> Trying ${REF}:${tag} (attempt ${attempt}/${PULL_ATTEMPTS})"
            tmp="$(mktemp -d)"

            # Attempt the pull directly rather than probing with `oras manifest
            # fetch`, whose subcommand varies across oras CLI versions. Keep
            # oras's own error: without it a lost cache is undiagnosable.
            if ! oras pull "${REF}:${tag}" -o "${tmp}" >/dev/null 2>"${tmp}/oras.err"; then
                reason="$(tr '\r' '\n' <"${tmp}/oras.err" | grep -v '^[[:space:]]*$' | tail -3 || true)"
                rm -rf "${tmp}"
                tmp=""

                # A missing tag is definitive, and it is the normal case for the
                # graph key on the first run after any junction change. Retrying
                # it just puts three alarming failures in the log.
                if printf '%s' "${reason}" | grep -qi 'not found'; then
                    echo "==> ${REF}:${tag} does not exist; trying the next tag"
                    break
                fi

                echo "==> Pull of ${REF}:${tag} failed:"
                if [ -n "${reason}" ]; then
                    printf '%s\n' "${reason}" | sed 's/^/    /'
                fi
                if [ "${attempt}" -lt "${PULL_ATTEMPTS}" ]; then
                    sleep 15
                fi
                continue
            fi

            if [ ! -f "${tmp}/cache.tar.zst" ]; then
                echo "==> ${REF}:${tag} carried no cache.tar.zst; trying the next tag"
                rm -rf "${tmp}"
                tmp=""
                break
            fi

            mkdir -p "${CACHE_DIR}"
            if zstd -d -c "${tmp}/cache.tar.zst" | tar -xf - -C "${CACHE_DIR}"; then
                rm -rf "${tmp}"
                tmp=""
                echo "==> Restored from ${REF}:${tag}"
                return 0
            fi

            # A truncated archive will not improve on retry.
            echo "==> Extracting ${REF}:${tag} failed; trying the next tag"
            rm -rf "${tmp}"
            tmp=""
            break
        done
    done

    echo "==> No usable cache at ${REF}; starting cold"
}

# latest is written on every run, success or failure, so a failed build still
# warms the next one. The graph key is written only when the caller passes one
# (CI passes it only on success), so a partial cache never claims to be the
# complete one for a graph.
push() {
    require_ref
    require_tools oras tar zstd
    login

    tmp="$(mktemp -d)"

    echo "==> Packing ${CACHE_DIR}"
    # cas/staging and cas/tmp are transient scratch; everything else is state.
    tar -cf - -C "${CACHE_DIR}" --exclude 'cas/staging' --exclude 'cas/tmp' . |
        zstd -T0 >"${tmp}/cache.tar.zst"
    du -h "${tmp}/cache.tar.zst" | awk '{print "    " $1}'

    # oras rejects absolute paths, so push from inside the temp directory.
    (
        cd "${tmp}"
        oras push "${REF}:latest" "cache.tar.zst:${MEDIA_TYPE}" >/dev/null
    )
    echo "==> Pushed ${REF}:latest"

    if [ -n "${KEY}" ]; then
        (
            cd "${tmp}"
            oras push "${REF}:${KEY}" "cache.tar.zst:${MEDIA_TYPE}" >/dev/null
        )
        echo "==> Pushed ${REF}:${KEY}"
    fi
}

case "${1:-}" in
pull) pull ;;
push) push ;;
*) usage ;;
esac
