#!/usr/bin/env bats
#
# Tests for the pull path of scripts/bst-cache-oci.sh. The artifact is ~12 GB
# and a failed pull costs a cold build, so the retry is behaviour worth pinning.
# `oras`, `zstd`, `tar`, and `sleep` are stubbed: the assertions are about the
# script's decisions, not the tools'.

setup() {
	REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
	SCRIPT="${REPO_ROOT}/scripts/bst-cache-oci.sh"
	SANDBOX="$(mktemp -d)"
	BIN="${SANDBOX}/bin"
	mkdir -p "${BIN}" "${SANDBOX}/cache"
	export PATH="${BIN}:${PATH}"
	export BST_CACHE_REF="example.test/cache"
	export BST_CACHE_DIR="${SANDBOX}/cache"
	export ORAS_LOG="${SANDBOX}/oras.log"
	unset BST_CACHE_KEY GH_TOKEN GITHUB_ACTOR
	: >"${ORAS_LOG}"

	# `oras pull <ref> -o <dir>` fails the first ${ORAS_FAILS} times, then
	# writes the archive the script expects.
	cat >"${BIN}/oras" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >>"${ORAS_LOG}"
case "${1:-}" in
login) exit 0 ;;
pull)
	out=""
	while [ "$#" -gt 0 ]; do
		case "$1" in
		-o)
			out="$2"
			shift 2
			;;
		*) shift ;;
		esac
	done
	attempts="$(grep -c '^pull ' "${ORAS_LOG}" || true)"
	if [ "${attempts}" -le "${ORAS_FAILS:-0}" ]; then
		echo "stub: transient failure (attempt ${attempts})" >&2
		exit 1
	fi
	if [ "${ORAS_NO_ARCHIVE:-0}" = "1" ]; then
		exit 0
	fi
	printf 'stub archive\n' >"${out}/cache.tar.zst"
	;;
esac
STUB
	chmod +x "${BIN}/oras"

	cat >"${BIN}/zstd" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
cat "${@: -1}"
STUB
	chmod +x "${BIN}/zstd"

	cat >"${BIN}/tar" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
cat >/dev/null
if [ "${TAR_FAILS:-0}" = "1" ]; then
	exit 1
fi
STUB
	chmod +x "${BIN}/tar"

	# The script backs off between attempts; the test should not.
	cat >"${BIN}/sleep" <<'STUB'
#!/usr/bin/env bash
exit 0
STUB
	chmod +x "${BIN}/sleep"
}

teardown() {
	rm -rf "${SANDBOX}"
}

@test "cache pull: tries the graph key before the rolling tag" {
	export BST_CACHE_KEY="bst-test-key"

	run "${SCRIPT}" pull
	[ "$status" -eq 0 ]
	[[ "${output}" == *"Trying example.test/cache:bst-test-key"* ]]
	[[ "${output}" == *"Restored from example.test/cache:bst-test-key"* ]]
	[ "$(grep -c '^pull ' "${ORAS_LOG}")" -eq 1 ]
}

@test "cache pull: retries a transient failure and restores" {
	export ORAS_FAILS=1

	run "${SCRIPT}" pull
	[ "$status" -eq 0 ]
	[[ "${output}" == *"Trying example.test/cache:latest (attempt 1/3)"* ]]
	[[ "${output}" == *"Pull of example.test/cache:latest failed:"* ]]
	[[ "${output}" == *"transient failure (attempt 1)"* ]]
	[[ "${output}" == *"Restored from example.test/cache:latest"* ]]
	[ "$(grep -c '^pull ' "${ORAS_LOG}")" -eq 2 ]
}

@test "cache pull: gives up after the attempts and starts cold" {
	export ORAS_FAILS=99

	run "${SCRIPT}" pull
	[ "$status" -eq 0 ]
	[[ "${output}" == *"No usable cache at example.test/cache; starting cold"* ]]
	[ "$(grep -c '^pull ' "${ORAS_LOG}")" -eq 3 ]
}

@test "cache pull: a tag with no archive does not retry" {
	export ORAS_NO_ARCHIVE=1

	run "${SCRIPT}" pull
	[ "$status" -eq 0 ]
	[[ "${output}" == *"carried no cache.tar.zst; trying the next tag"* ]]
	[ "$(grep -c '^pull ' "${ORAS_LOG}")" -eq 1 ]
}

@test "cache pull: a bad archive does not retry" {
	export TAR_FAILS=1

	run "${SCRIPT}" pull
	[ "$status" -eq 0 ]
	[[ "${output}" == *"Extracting example.test/cache:latest failed; trying the next tag"* ]]
	[ "$(grep -c '^pull ' "${ORAS_LOG}")" -eq 1 ]
}
