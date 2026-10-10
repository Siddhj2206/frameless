#!/usr/bin/env bats
#
# Unit tests for the root Justfile `clean` recipe — the one recipe that runs
# `rm -rf` against the working tree. The blast radius (what it deletes, what it
# must leave alone) is asserted against a sandbox copy of the Justfile, so the
# deletions only ever touch throwaway files.

setup() {
	REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
	SANDBOX="$(mktemp -d)"
	cp "${REPO_ROOT}/Justfile" "${SANDBOX}/Justfile"
}

teardown() {
	rm -rf "${SANDBOX}"
}

run_recipe() {
	run just --justfile "${SANDBOX}/Justfile" --working-directory "${SANDBOX}" "$@"
}

@test "clean: removes the export and disk-image artifacts" {
	mkdir -p "${SANDBOX}/.build-out/oci" "${SANDBOX}/output/qcow2"
	touch "${SANDBOX}/.build-out/oci/index.json" \
		"${SANDBOX}/output/qcow2/disk.qcow2" \
		"${SANDBOX}/bootable.raw" \
		"${SANDBOX}/bootable.qcow2" \
		"${SANDBOX}/.ovmf-vars.fd"

	run_recipe clean
	[ "$status" -eq 0 ]

	[ ! -e "${SANDBOX}/.build-out" ]
	[ ! -e "${SANDBOX}/output" ]
	[ ! -e "${SANDBOX}/bootable.raw" ]
	[ ! -e "${SANDBOX}/bootable.qcow2" ]
	[ ! -e "${SANDBOX}/.ovmf-vars.fd" ]
}

@test "clean: leaves the source tree alone" {
	mkdir -p "${SANDBOX}/elements" "${SANDBOX}/custom"
	touch "${SANDBOX}/elements/image.bst" \
		"${SANDBOX}/custom/keep" \
		"${SANDBOX}/project.conf" \
		"${SANDBOX}/README.md"

	run_recipe clean
	[ "$status" -eq 0 ]

	[ -f "${SANDBOX}/elements/image.bst" ]
	[ -f "${SANDBOX}/custom/keep" ]
	[ -f "${SANDBOX}/project.conf" ]
	[ -f "${SANDBOX}/README.md" ]
	[ -f "${SANDBOX}/Justfile" ]
}

@test "clean: does not descend below the top level" {
	mkdir -p "${SANDBOX}/keepdir/output"
	touch "${SANDBOX}/keepdir/output/manifest"

	run_recipe clean
	[ "$status" -eq 0 ]

	[ -f "${SANDBOX}/keepdir/output/manifest" ]
}

@test "clean: succeeds on an already-clean tree and is repeatable" {
	run_recipe clean
	[ "$status" -eq 0 ]

	run_recipe clean
	[ "$status" -eq 0 ]
	[ -f "${SANDBOX}/Justfile" ]
}

@test "clean: does not delete the working directory itself" {
	run_recipe clean
	[ "$status" -eq 0 ]
	[ -d "${SANDBOX}" ]
	[ -f "${SANDBOX}/Justfile" ]
}
