###############################################################################
# OCI image assembly
###############################################################################
# The default target. Stages the filtered root at /layer, runs the
# post-install steps that make the filesystem bootable, then hands it to
# freedesktop-sdk's build-oci to emit an OCI layout with the bootc label.
#
# Build it with:  just bst build oci/image.bst
# Checkout:       just bst artifact checkout oci/image.bst --directory out
#
# The label values come from project.conf's identity variables; the os-release
# element is #18's.
###############################################################################
kind: script

build-depends:
  - gnome-build-meta.bst:freedesktop-sdk.bst:components/fakecap.bst
  - gnome-build-meta.bst:freedesktop-sdk.bst:components/oci-builder.bst
  - freedesktop-sdk.bst:components/glib.bst
  - gnome-build-meta.bst:core-deps/dconf.bst
  - gnome-build-meta.bst:freedesktop-sdk.bst:vm/prepare-image.bst
  - oci/layers/image-init-scripts.bst
  - filename: oci/layers/image.bst
    config:
      location: /layer

environment:
  LD_PRELOAD: /usr/libexec/fakecap/fakecap.so
  FAKECAP_DB: /fakecap

variables:
  (@):
    - include/fsdk-version.yml
  # Seeds /etc/machine-id deterministically; bootc regenerates it on deploy.
  sysroot-seed: b57666f6-0fe5-4310-adff-f256936d164d

config:
  commands:
    - mkdir /fakecap

    # Apply the collected initial scripts (sysusers, tmpfiles, units).
    - |
      prepare-image.sh \
         --sysroot /layer \
         --initscripts /initial_scripts \
         --seed "%{sysroot-seed}" \
         --noroot --noboot >/dev/null

    - |
      systemd-sysusers --root /layer

    - |
      glib-compile-schemas /layer/usr/share/glib-2.0/schemas

    # bootc images must not ship both /etc and /usr/etc.
    - |
      if [ -d /layer/usr/etc ]; then
        mkdir -p /layer/etc
        cp -a /layer/usr/etc/. /layer/etc/
        rm -rf /layer/usr/etc
      fi

    - |
      dconf update /layer/etc/dconf/db

    # Rebuild the linker cache for the sysroot. A stale cache breaks dlopen()
    # for any library whose SO version moved, silently, on first boot.
    - |
      ldconfig -r /layer -f /layer/etc/ld.so.conf

    - |
      cd "%{install-root}"
      build-oci <<EOF
      mode: oci
      gzip: disabled
      images:
      - os: linux
        architecture: "%{go-arch}"
        layer: /layer
        comment: "Import frameless layer"
        config:
          Labels:
            'com.github.containers.toolbox': 'true'
            'org.opencontainers.image.title': '%{project-name}'
            'org.opencontainers.image.description': '%{image-description}'
            'org.opencontainers.image.vendor': '%{image-vendor}'
            'org.opencontainers.image.version': '%{fsdk-version}'
            'org.opencontainers.image.licenses': 'Apache-2.0'
            'org.opencontainers.image.source': 'https://github.com/Siddhj2206/frameless'
            'containers.bootc': '1'
        index-annotations:
          'org.opencontainers.image.ref.name': 'ghcr.io/%{image-vendor}/%{project-name}:latest'
      EOF
