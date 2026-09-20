#!/usr/bin/env bats
# Contract: image identity has one source of truth.
#
# project.conf holds the name and vendor; the os-release generator and the OCI
# assembly must consume them by reference (%{project-name}, %{image-vendor}),
# never restate them. A fork that hardcodes a name ships an image that
# misidentifies itself.
#
# This is the static half of the contract. The built os-release is checked once
# the image graph builds (integration tests).

REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
PROJECT_CONF="${REPO_ROOT}/project.conf"
OS_RELEASE_YML="${REPO_ROOT}/include/os-release.yml"
OCI_IMAGE="${REPO_ROOT}/elements/oci/image.bst"

project_name() { sed -n 's/^name: //p' "${PROJECT_CONF}"; }
project_vendor() { sed -n 's/^  image-vendor: //p' "${PROJECT_CONF}"; }
project_description() { sed -n 's/^  image-description: //p' "${PROJECT_CONF}"; }

@test "identity: project.conf declares exactly one name" {
    run project_name
    [ "$status" -eq 0 ]
    [ -n "${output}" ]
    [ "$(printf '%s\n' "${output}" | wc -l)" -eq 1 ]
}

@test "identity: project.conf declares vendor and description" {
    run project_vendor
    [ -n "${output}" ]
    run project_description
    [ -n "${output}" ]
}

@test "identity: the os-release generator references the project identity" {
    grep -Fq 'IMAGE_NAME: "%{project-name}"' "${OS_RELEASE_YML}"
    grep -Fq 'IMAGE_VENDOR: "%{image-vendor}"' "${OS_RELEASE_YML}"
    grep -Fq 'IMAGE_REF: "ostree-image-signed:docker://ghcr.io/%{image-vendor}/%{project-name}"' "${OS_RELEASE_YML}"
}

@test "identity: the os-release generator does not hardcode the project name" {
    local name
    name="$(project_name)"
    ! grep -Fq "IMAGE_NAME: \"${name}\"" "${OS_RELEASE_YML}"
}

@test "identity: the os-release generator carries the contract fields" {
    grep -Fq 'NAME="${IMAGE_PRETTY_NAME}"' "${OS_RELEASE_YML}"
    grep -Fq 'PRETTY_NAME="${IMAGE_PRETTY_NAME}"' "${OS_RELEASE_YML}"
    grep -Fq 'IMAGE_NAME="${IMAGE_NAME}"' "${OS_RELEASE_YML}"
    grep -Fq 'IMAGE_VENDOR="${IMAGE_VENDOR}"' "${OS_RELEASE_YML}"
    grep -Fq 'IMAGE_REF="${IMAGE_REF}"' "${OS_RELEASE_YML}"
}

@test "identity: the generator writes image-info.json with the ublue fields" {
    grep -Fq '"image-name"' "${OS_RELEASE_YML}"
    grep -Fq '"image-ref"' "${OS_RELEASE_YML}"
    grep -Fq '"image-vendor"' "${OS_RELEASE_YML}"
    grep -Fq '"image-tag"' "${OS_RELEASE_YML}"
}

@test "identity: the OCI ref.name matches the IMAGE_REF owner and name" {
    grep -Fq "'org.opencontainers.image.ref.name': 'ghcr.io/%{image-vendor}/%{project-name}:latest'" "${OCI_IMAGE}"
}
