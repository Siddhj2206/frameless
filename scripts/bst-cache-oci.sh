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
# Environment:
#   BST_CACHE_REF  required. e.g. ghcr.io/owner/repo-cache
#   BST_CACHE_KEY  optional. A graph-derived key; when set, a second tag is
#                  written so a cache matching the current graph can be
#                  preferred over the rolling one.
#   BST_CACHE_DIR  optional. Defaults to ~/.cache/buildstream.
#   GH_TOKEN, GITHUB_ACTOR  optional. Used to log in when both are set.

set -euo pipefail

MEDIA_TYPE="application/vnd.buildstream.cas.tar.zst"
CACHE_DIR="${BST_CACHE_DIR:-${HOME}/.cache/buildstream}"
REF="${BST_CACHE_REF:-}"
KEY="${BST_CACHE_KEY:-}"

usage() {
    echo "usage: $(basename "$0") {pull|push}" >&2
    exit 2
}

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
# different graph, but BuildStream still uses whatever artifacts match.
pull() {
    require_ref
    require_tools oras tar zstd
    login

    local tag tmp
    for tag in ${KEY:+"${KEY}"} latest; do
        if ! oras manifest fetch "${REF}:${tag}" >/dev/null 2>&1; then
            continue
        fi
        echo "==> Restoring BuildStream cache from ${REF}:${tag}"
        tmp="$(mktemp -d)"
        oras pull "${REF}:${tag}" -o "${tmp}"
        mkdir -p "${CACHE_DIR}"
        # The CAS is large; stream it rather than unpacking to an intermediate.
        zstd -d -c "${tmp}/cache.tar.zst" | tar -xf - -C "${CACHE_DIR}"
        rm -rf "${tmp}"
        echo "==> Restored"
        return 0
    done

    echo "==> No cache at ${REF}; starting cold"
}

# latest is written on every run, success or failure, so a failed build still
# warms the next one. The graph key is written only when the caller passes one
# (CI passes it only on success), so a partial cache never claims to be the
# complete one for a graph.
push() {
    require_ref
    require_tools oras tar zstd
    login

    local tmp
    tmp="$(mktemp -d)"
    trap 'rm -rf "${tmp}"' EXIT

    echo "==> Packing ${CACHE_DIR}"
    # cas/staging and cas/tmp are transient scratch; everything else is state.
    tar -cf - -C "${CACHE_DIR}" --exclude 'cas/staging' --exclude 'cas/tmp' . \
        | zstd -T0 > "${tmp}/cache.tar.zst"
    du -h "${tmp}/cache.tar.zst" | awk '{print "    " $1}'

    oras push "${REF}:latest" "${tmp}/cache.tar.zst:${MEDIA_TYPE}" >/dev/null
    echo "==> Pushed ${REF}:latest"

    if [ -n "${KEY}" ]; then
        oras push "${REF}:${KEY}" "${tmp}/cache.tar.zst:${MEDIA_TYPE}" >/dev/null
        echo "==> Pushed ${REF}:${KEY}"
    fi
}

case "${1:-}" in
pull) pull ;;
push) push ;;
*) usage ;;
esac
