# frameless — a BuildStream template for building your own OS image.
#
# Everything that touches the image graph goes through `just bst`, which runs
# BuildStream inside the pinned freedesktop-sdk container. The recipes below are
# the local loop: build the OCI image, load it into podman, install it to a disk,
# and boot it.

# List available commands.
[group('info')]
default:
    @just --list

# ── Configuration ─────────────────────────────────────────────────────
export image_name := env("BUILD_IMAGE_NAME", "frameless")
export image_tag := env("BUILD_IMAGE_TAG", "latest")
export base_dir := env("BUILD_BASE_DIR", ".")
export filesystem := env("BUILD_FILESYSTEM", "btrfs")

# BuildStream container image used by local runs and CI. Pinned to a digest for
# reproducibility; override with BST2_IMAGE. This digest carries BuildStream 2.8,
# matching project.conf's min-version — the runner and min-version are one
# decision.
export bst2_image := env("BST2_IMAGE", "registry.gitlab.com/freedesktop-sdk/infrastructure/freedesktop-sdk-docker-images/bst2@sha256:b090811a617cb4c11c8ab9b08aa272a6b90c58cb289193f178ea5ca4d3ced681")

# VM settings.
export vm_ram := env("VM_RAM", "8192")
export vm_cpus := env("VM_CPUS", "4")

# OCI metadata, applied at export time. Empty means "leave the build-time value".
export OCI_IMAGE_CREATED := env("OCI_IMAGE_CREATED", "")
export OCI_IMAGE_REVISION := env("OCI_IMAGE_REVISION", "")

# The FSDK release, parsed from the pinned junction ref in
# elements/freedesktop-sdk.bst — the single source of truth for the image
# version. e.g. "26.08.1". The `bst` recipe writes it into
# include/fsdk-version.yml for elements to read as %{fsdk-version}.
export fsdk_version := `grep -E '^\s*ref:' elements/freedesktop-sdk.bst | head -1 | sed -E 's/.*freedesktop-sdk-//; s/-[0-9]+-g[0-9a-f]+$//'`
# The exact junction ref, for provenance and release notes.
export fsdk_ref := `grep -E '^\s*ref:' elements/freedesktop-sdk.bst | head -1 | sed -E 's/^\s*ref:\s*//'`

# ── BuildStream wrapper ──────────────────────────────────────────────
# Run any bst command inside the pinned bst2 container via podman, so no local
# BuildStream install is needed. Set BST_RUNNER to an alternate runner (used by
# tests), BST_FLAGS to append flags, BST_PODMAN_EXTRA_ARGS for podman flags.
#
# Usage: just bst build oci/image.bst
# just bst show --deps all oci/image.bst
[group('dev')]
bst *ARGS:
    #!/usr/bin/env bash
    set -euo pipefail
    # Regenerate include/fsdk-version.yml from the pinned FSDK junction ref, so
    # elements consume %{fsdk-version} without re-parsing it. Gitignored; never
    # hand-edited. Every bst entry point goes through here, including CI.
    printf 'fsdk-version: "%s"\n' "{{ fsdk_version }}" > include/fsdk-version.yml
    if [ -n "${BST_RUNNER:-}" ]; then
        exec "$BST_RUNNER" {{ ARGS }}
    fi
    mkdir -p "${HOME}/.cache/buildstream"
    # Word-splitting on the optional flags is intentional.
    # shellcheck disable=SC2086
    podman run --rm \
        --privileged \
        --device /dev/fuse \
        --network=host \
        ${BST_PODMAN_EXTRA_ARGS:-} \
        -v "{{ justfile_directory() }}:/src:rw" \
        -v "${HOME}/.cache/buildstream:/root/.cache/buildstream:rw" \
        -w /src \
        "{{ bst2_image }}" \
        bash -c 'bst --colors "$@"' -- --no-interactive ${BST_FLAGS:-} {{ ARGS }}

# ── Info ─────────────────────────────────────────────────────────────
# The OCI tags to publish for this build, one per line: the minor stream and the
# exact FSDK release. CI appends the branch tags (:stable-testing, :stable).
[group('info')]
tags:
    #!/usr/bin/env bash
    set -euo pipefail
    v="{{ fsdk_version }}"
    minor="$(grep -oE '^[0-9]+\.[0-9]+' <<<"${v}")"
    printf '%s\n' "${minor}"
    if [[ "${v}" != "${minor}" ]]; then
        printf '%s\n' "${v}"
    fi

# ── Build ─────────────────────────────────────────────────────────────
# Build the OCI image and load it into podman as {{ image_name }}:{{ image_tag }}.
[group('build')]
build: export

# Check out the built OCI layout, load it into podman, and apply metadata labels.
#
# The graph is assembled by BuildStream; this only moves the result into podman
# so `bootc`/`generate-bootable-image` and a push can use it. Nothing here edits
# the image graph.
[group('build')]
export:
    #!/usr/bin/env bash
    set -euo pipefail

    SUDO_CMD=""
    if [ "$(id -u)" -ne 0 ]; then
        SUDO_CMD="sudo"
    fi

    echo "==> Building oci/image.bst..."
    just bst build oci/image.bst

    echo "==> Exporting OCI image → {{ image_name }}:{{ image_tag }}..."
    rm -rf .build-out
    just bst artifact checkout oci/image.bst --directory /src/.build-out

    # `podman pull` (not skopeo) keeps the loaded view intact for a later push.
    IMAGE_ID=$($SUDO_CMD podman pull -q oci:.build-out)
    IMAGE_ID=${IMAGE_ID#sha256:}
    if [[ ! "$IMAGE_ID" =~ ^[0-9a-f]{64}$ ]]; then
        echo "ERROR: podman returned an invalid image ID: $IMAGE_ID" >&2
        exit 1
    fi
    rm -rf .build-out

    # Dynamic provenance labels, applied only when set. The build-time labels
    # (title, version, source) come from the graph; these are per-build.
    LABEL_ARGS=()
    [ -n "${OCI_IMAGE_CREATED}" ] && LABEL_ARGS+=(--label "org.opencontainers.image.created=${OCI_IMAGE_CREATED}")
    [ -n "${OCI_IMAGE_REVISION}" ] && LABEL_ARGS+=(--label "org.opencontainers.image.revision=${OCI_IMAGE_REVISION}")

    if [ "${#LABEL_ARGS[@]}" -gt 0 ]; then
        printf 'FROM %s\n' "$IMAGE_ID" \
            | $SUDO_CMD podman build --pull=never --security-opt label=type:unconfined_t \
                "${LABEL_ARGS[@]}" -t "{{ image_name }}:{{ image_tag }}" -f - .
        $SUDO_CMD podman rmi "$IMAGE_ID" >/dev/null 2>&1 || true
    else
        $SUDO_CMD podman tag "$IMAGE_ID" "{{ image_name }}:{{ image_tag }}"
    fi

    echo "==> Loaded {{ image_name }}:{{ image_tag }}"

# ── Run ──────────────────────────────────────────────────────────────
# Run bootc against the loaded image, e.g.
# just bootc install to-disk --via-loopback /data/bootable.raw ...
[group('run')]
bootc *ARGS:
    sudo podman run \
        --rm --privileged --pid=host -it \
        -v /var/lib/containers:/var/lib/containers \
        -v /dev:/dev \
        -v "{{ base_dir }}:/data" \
        --security-opt label=type:unconfined_t \
        "{{ image_name }}:{{ image_tag }}" bootc {{ ARGS }}

# Install the loaded image to a bootable raw disk image via bootc.
[group('run')]
generate-bootable-image:
    #!/usr/bin/env bash
    set -euo pipefail

    if ! sudo podman image exists "{{ image_name }}:{{ image_tag }}"; then
        echo "ERROR: {{ image_name }}:{{ image_tag }} not found. Run 'just build' first." >&2
        exit 1
    fi

    if [ ! -e "{{ base_dir }}/bootable.raw" ]; then
        echo "==> Creating a 30G sparse disk image..."
        fallocate -l 30G "{{ base_dir }}/bootable.raw"
    fi

    echo "==> Installing {{ image_name }}:{{ image_tag }} to disk via bootc..."
    just bootc install to-disk \
        --via-loopback /data/bootable.raw \
        --filesystem "{{ filesystem }}" \
        --wipe \
        --composefs-backend \
        --bootloader systemd \
        --karg systemd.firstboot=no \
        --karg splash \
        --karg quiet

    rm -f "{{ base_dir }}/bootable.qcow2"
    echo "==> Bootable disk image ready: {{ base_dir }}/bootable.raw"

# Boot the raw disk image in a VM. Native qemu when available, else a container.
[group('run')]
boot-vm:
    #!/usr/bin/env bash
    set -euo pipefail

    DISK=$(realpath "{{ base_dir }}/bootable.raw")
    if [ ! -e "$DISK" ]; then
        echo "ERROR: ${DISK} not found. Run 'just generate-bootable-image' first." >&2
        exit 1
    fi

    if command -v qemu-system-x86_64 &>/dev/null; then
        echo "==> Booting ${DISK} with native qemu (UEFI, KVM)..."

        OVMF_CODE=""
        for candidate in \
            /usr/share/edk2/ovmf/OVMF_CODE.fd \
            /usr/share/OVMF/OVMF_CODE.fd \
            /usr/share/OVMF/OVMF_CODE_4M.fd \
            /usr/share/edk2/x64/OVMF_CODE.4m.fd \
            /usr/share/qemu/OVMF_CODE.fd; do
            [ -f "$candidate" ] && { OVMF_CODE="$candidate"; break; }
        done
        if [ -z "$OVMF_CODE" ]; then
            echo "ERROR: OVMF firmware not found — install edk2-ovmf (Fedora) or ovmf (Debian/Ubuntu)." >&2
            exit 1
        fi

        OVMF_VARS="{{ base_dir }}/.ovmf-vars.fd"
        if [ ! -e "$OVMF_VARS" ]; then
            OVMF_VARS_SRC=""
            for candidate in \
                /usr/share/edk2/ovmf/OVMF_VARS.fd \
                /usr/share/OVMF/OVMF_VARS.fd \
                /usr/share/OVMF/OVMF_VARS_4M.fd \
                /usr/share/edk2/x64/OVMF_VARS.4m.fd \
                /usr/share/qemu/OVMF_VARS.fd; do
                [ -f "$candidate" ] && { OVMF_VARS_SRC="$candidate"; break; }
            done
            [ -z "$OVMF_VARS_SRC" ] && { echo "ERROR: OVMF_VARS not found." >&2; exit 1; }
            cp "$OVMF_VARS_SRC" "$OVMF_VARS"
        fi

        qemu-system-x86_64 \
            -enable-kvm \
            -m "{{ vm_ram }}" \
            -cpu host \
            -smp "{{ vm_cpus }}" \
            -drive "file=${DISK},format=raw,if=virtio" \
            -drive "if=pflash,format=raw,readonly=on,file=${OVMF_CODE}" \
            -drive "if=pflash,format=raw,file=${OVMF_VARS}" \
            -device virtio-vga \
            -display gtk \
            -device virtio-keyboard \
            -device virtio-mouse \
            -device virtio-net-pci,netdev=net0 \
            -netdev "user,id=net0,hostfwd=tcp:127.0.0.1:2222-:22"
    else
        echo "==> qemu-system-x86_64 not found; falling back to ghcr.io/qemus/qemu..."
        BOOT_MOUNT="/boot.img"
        if [ -e "{{ base_dir }}/bootable.qcow2" ]; then
            DISK=$(realpath "{{ base_dir }}/bootable.qcow2")
            BOOT_MOUNT="/boot.qcow2"
        fi

        port=8006
        while ss -tunalp 2>/dev/null | grep -q ":${port} "; do
            port=$(( port + 1 ))
        done
        echo "==> Web console: http://localhost:${port}"

        podman run \
            --rm --privileged \
            --device /dev/kvm \
            --pull=always \
            --publish "127.0.0.1:${port}:8006" \
            --publish "127.0.0.1:2222:22" \
            --env "USER_PORTS=22" \
            --env "NETWORK=user" \
            --env "CPU_CORES={{ vm_cpus }}" \
            --env "RAM_SIZE={{ vm_ram }}" \
            --env "TPM=y" \
            --env "BOOT_MODE=uefi" \
            --env "ARGUMENTS=-snapshot" \
            --volume "${DISK}:${BOOT_MOUNT}" \
            ghcr.io/qemus/qemu:latest
    fi

# Convert the raw disk image to qcow2.
[group('run')]
convert-to-qcow2:
    #!/usr/bin/env bash
    set -euo pipefail

    RAW="{{ base_dir }}/bootable.raw"
    QCOW2="{{ base_dir }}/bootable.qcow2"

    if [ ! -e "$RAW" ]; then
        echo "ERROR: ${RAW} not found. Run 'just generate-bootable-image' first." >&2
        exit 1
    fi

    echo "==> Converting ${RAW} to ${QCOW2}..."
    if command -v qemu-img &>/dev/null; then
        qemu-img convert -f raw -O qcow2 "$RAW" "$QCOW2"
    else
        podman run --rm \
            -v "{{ base_dir }}:/data" \
            --entrypoint qemu-img \
            ghcr.io/qemus/qemu:latest \
            convert -f raw -O qcow2 "/data/bootable.raw" "/data/bootable.qcow2"
    fi
    echo "==> Conversion complete: ${QCOW2}"

# ── Test ─────────────────────────────────────────────────────────────
# Run the contract suite: interfaces the image must satisfy. A fork keeps these.
[group('test')]
test-contract:
    #!/usr/bin/bash
    set -euo pipefail
    just _bats tests/contract

# Run the template suite: this repository's build wiring. A fork may delete this.
[group('test')]
test-template:
    #!/usr/bin/bash
    set -euo pipefail
    just _bats tests/template

# Run every unit test (contract + template). CI calls this.
[group('test')]
test-unit:
    #!/usr/bin/bash
    set -euo pipefail
    just _bats tests

# Single definition of how the suite runs: discover every *_test.bats under the
# given directory, so a fork can add or remove files without editing this file.
[private]
_bats $dir:
    #!/usr/bin/bash
    set -euo pipefail
    if ! command -v bats &>/dev/null; then
        echo "bats not found — install with: sudo apt-get install bats  OR  npm install -g bats"
        exit 1
    fi
    mapfile -t files < <(find "{{ dir }}" -type f -name '*_test.bats' | sort)
    if [[ ${#files[@]} -eq 0 ]]; then
        echo "No *_test.bats files found under {{ dir }}" >&2
        exit 1
    fi
    echo "Running ${#files[@]} test files..."
    bats --print-output-on-failure "${files[@]}"

# Validate Brewfiles without evaluating them as Ruby.
[group('test')]
validate-brewfiles:
    #!/usr/bin/bash
    set -euo pipefail
    bash scripts/validate-brewfiles.sh

# Validate flatpak preinstall files against flathub (Branch= key + app existence).
[group('test')]
validate-flatpaks:
    #!/usr/bin/bash
    set -euo pipefail
    bash scripts/validate-flatpaks.sh

# ── Dev ──────────────────────────────────────────────────────────────
# Check Justfile syntax (and every *.just).
[group('dev')]
check:
    just _format-justfiles "--check"

# Rewrite every justfile in place, or report drift instead when passed --check.
[private]
_format-justfiles $mode="":
    #!/usr/bin/bash
    set -euo pipefail
    echo "Checking syntax: Justfile"
    just --unstable --fmt {{ mode }} -f Justfile
    while IFS= read -r -d '' file; do
        echo "Checking syntax: ${file}"
        just --unstable --fmt {{ mode }} -f "${file}"
    done < <(find . -type f -name '*.just' -print0)

# Fix Justfile syntax in place.
[group('dev')]
fix:
    just _format-justfiles

# The repository's shell scripts: the *.sh files git tracks. Single definition of
# the lint and format scope.
[private]
shell-sources:
    #!/usr/bin/env bash
    set -euo pipefail
    git ls-files '*.sh'

# Shellcheck the shell scripts git tracks.
[group('dev')]
lint:
    #!/usr/bin/env bash
    set -euo pipefail
    if ! command -v shellcheck &>/dev/null; then
        echo "shellcheck could not be found. Please install it."
        exit 1
    fi
    mapfile -t sources < <(just shell-sources)
    if [[ ${#sources[@]} -eq 0 ]]; then
        echo "No shell scripts found: git tracks no *.sh files" >&2
        exit 1
    fi
    printf 'Shellchecking %s scripts:\n' "${#sources[@]}"
    printf '  %s\n' "${sources[@]}"
    shellcheck "${sources[@]}"

# Format the shell scripts git tracks with shfmt.
[group('dev')]
format:
    #!/usr/bin/env bash
    set -euo pipefail
    if ! command -v shfmt &>/dev/null; then
        echo "shfmt could not be found. Please install it."
        exit 1
    fi
    mapfile -t sources < <(just shell-sources)
    if [[ ${#sources[@]} -eq 0 ]]; then
        echo "No shell scripts found: git tracks no *.sh files" >&2
        exit 1
    fi
    printf 'Formatting %s scripts:\n' "${#sources[@]}"
    printf '  %s\n' "${sources[@]}"
    shfmt --write "${sources[@]}"

# Remove generated artifacts.
[group('dev')]
clean:
    #!/usr/bin/bash
    set -euo pipefail
    rm -rf .build-out output bootable.raw bootable.qcow2 .ovmf-vars.fd
