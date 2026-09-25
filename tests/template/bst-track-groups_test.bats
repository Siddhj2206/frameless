#!/usr/bin/env bats
#
# Tests for scripts/bst-track-groups.sh, which decides what `just track` moves
# and how the weekly tracker splits its pull requests. The script reads the
# tree, so the assertions are about the rule — a group is an element's directory
# under elements/, a root element is its own group — rather than a fixed list.
# A fork that adds elements needs no edit here.

setup() {
	REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
	SCRIPT="${REPO_ROOT}/scripts/bst-track-groups.sh"
}

# Every element whose sources declare `track:`, sorted.
trackable_elements() {
	(cd "${REPO_ROOT}" && grep -rl --include='*.bst' -E '^[[:space:]]*track:' elements | sort)
}

# Every element the script reports, across all groups, sorted.
reported_elements() {
	(
		cd "${REPO_ROOT}" || exit 1
		mapfile -t groups < <("${SCRIPT}")
		for group in "${groups[@]}"; do "${SCRIPT}" "${group}"; done | sort
	)
}

@test "track groups: every trackable element is reported exactly once" {
	run trackable_elements
	[ "$status" -eq 0 ]
	[ -n "${output}" ]

	local expected actual
	expected="${output}"
	actual="$(reported_elements)"
	[ "${actual}" = "${expected}" ]
}

@test "track groups: no element without a track: ref is reported" {
	local element
	while read -r element; do
		grep -qE '^[[:space:]]*track:' "${REPO_ROOT}/${element}"
	done < <(reported_elements)
}

@test "track groups: group names are listed once each" {
	local listed unique
	listed="$(cd "${REPO_ROOT}" && "${SCRIPT}")"
	unique="$(printf '%s\n' "${listed}" | sort -u)"
	[ -n "${listed}" ]
	[ "${listed}" = "${unique}" ]
}

@test "track groups: every group has at least one element" {
	local group
	while read -r group; do
		run bash -c "cd '${REPO_ROOT}' && '${SCRIPT}' '${group}'"
		[ "$status" -eq 0 ]
		[ -n "${output}" ]
	done < <(cd "${REPO_ROOT}" && "${SCRIPT}")
}

@test "track groups: a root element is its own group, a nested one groups by directory" {
	local root_element nested_element group
	root_element="$(trackable_elements | grep -E '^elements/[^/]+\.bst$' | head -1)"
	nested_element="$(trackable_elements | grep -E '^elements/[^/]+/[^/]+\.bst$' | head -1)"

	# The fixture is the repository's own layout; fail loudly if it changes
	# shape rather than passing vacuously.
	[ -n "${root_element}" ]
	[ -n "${nested_element}" ]

	group="$(cd "${REPO_ROOT}" && "${SCRIPT}" | grep -Fx "$(basename "${root_element%.bst}")")"
	[ -n "${group}" ]
	group="$(cd "${REPO_ROOT}" && "${SCRIPT}" | grep -Fx "$(basename "$(dirname "${nested_element}")")")"
	[ -n "${group}" ]
}

@test "track groups: an unknown group fails with a message" {
	run bash -c "cd '${REPO_ROOT}' && '${SCRIPT}' no-such-group"
	[ "$status" -ne 0 ]
	[[ "${output}" == *"no group named no-such-group"* ]]
}
