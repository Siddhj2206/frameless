#!/usr/bin/env bats
# Contract: the image version comes from the FSDK junction ref, one source.
#
# `just bst` regenerates include/fsdk-version.yml from the pinned ref; the
# os-release element and the OCI labels consume %{fsdk-version}. If the parse
# here and the Justfile's diverge, the image version drifts silently.

REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
FSDK="${REPO_ROOT}/elements/freedesktop-sdk.bst"
OS_RELEASE="${REPO_ROOT}/include/os-release.yml"
OS_RELEASE_ELEMENT="${REPO_ROOT}/elements/oci/os-release.bst"
OCI_IMAGE="${REPO_ROOT}/elements/oci/image.bst"
JUSTFILE="${REPO_ROOT}/Justfile"

# The parse the Justfile uses, kept identical on purpose.
fsdk_version() {
    grep -E '^\s*ref:' "${FSDK}" | head -1 | sed -E 's/.*freedesktop-sdk-//; s/-[0-9]+-g[0-9a-f]+$//'
}

@test "version: the FSDK ref parses to a release" {
    run fsdk_version
    [ "$status" -eq 0 ]
    [[ "${output}" =~ ^[0-9]+\.[0-9]+ ]]
}

@test "version: the Justfile defines fsdk_version from the junction ref" {
    grep -Fq "ref:' elements/freedesktop-sdk.bst" "${JUSTFILE}"
}

@test "version: os-release takes VERSION, VERSION_ID and IMAGE_VERSION from fsdk-version" {
    grep -Fq 'VERSION: "%{fsdk-version}"' "${OS_RELEASE}"
    grep -Fq 'VERSION_ID: "%{fsdk-version}"' "${OS_RELEASE}"
    grep -Fq 'IMAGE_VERSION: "%{fsdk-version}"' "${OS_RELEASE}"
}

@test "version: the os-release element includes the generated version file" {
    grep -Fq 'include/fsdk-version.yml' "${OS_RELEASE_ELEMENT}"
}

@test "version: the OCI labels carry the version" {
    grep -Fq "'org.opencontainers.image.version': '%{fsdk-version}'" "${OCI_IMAGE}"
}
