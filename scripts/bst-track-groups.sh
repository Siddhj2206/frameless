#!/usr/bin/env bash
# Source-track groups: the elements `bst source track` can actually move,
# grouped by their directory under elements/. An element at the root of
# elements/ is its own group.
#
# Derived from the tree, so a fork never maintains a list — and an element whose
# sources are pinned outright (a tarball with only a `ref:`) is never listed,
# because there is nothing to track.
#
# Renovate cannot do this job: `track:` is BuildStream's symbolic-tracking field
# and only `bst source track` resolves it, across git, docker, and pypi sources
# alike. See docs/research/11-renovate-config.md.
#
# Usage:
#   bst-track-groups.sh             list the group names
#   bst-track-groups.sh <group>     list that group's elements
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

mapfile -t rows < <(
    grep -rl --include='*.bst' -E '^[[:space:]]*track:' elements |
        sort |
        while read -r element; do
            relative="${element#elements/}"
            group="${relative%%/*}"
            printf '%s %s\n' "${group%.bst}" "${element}"
        done
)

if [ "$#" -eq 0 ]; then
    for row in "${rows[@]}"; do
        printf '%s\n' "${row%% *}"
    done | uniq
    exit 0
fi

group="$1"
found=""
for row in "${rows[@]}"; do
    if [ "${row%% *}" = "${group}" ]; then
        printf '%s\n' "${row#* }"
        found=1
    fi
done

if [ -z "${found}" ]; then
    printf 'bst-track-groups.sh: no group named %s\n' "${group}" >&2
    printf 'Run without arguments to list the groups.\n' >&2
    exit 1
fi
