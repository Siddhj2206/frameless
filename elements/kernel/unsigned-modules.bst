###############################################################################
# Unsigned kernel modules
###############################################################################
# Replaces gnome-build-meta's gnomeos/initramfs/signed-modules.bst, which signs
# every kernel module with files/boot-keys/MODULES.key. That private key is not
# in the public gnome-build-meta repository — only the Makefile and snakeoil
# material are — so the element fails to load in a fork with
#   Specified path 'files/boot-keys/MODULES.key' does not exist
# frameless does not enforce kernel module signatures, so stage the modules and
# their vmlinuz unsigned instead.
###############################################################################
kind: manual

build-depends:
  - core/sandbox-tools.bst
  # Resolve to whatever element supplies the kernel's modules, so a kernel
  # override at the junction boundary still co-versions with this.
  - filename: freedesktop-sdk.bst:components/linux.bst
    strict: true
  - freedesktop-sdk.bst:public-stacks/runtime-minimal.bst

variables:
  strip-binaries: ""

config:
  install-commands:
    - |
      mkdir -p "%{install-root}/usr/lib"
      cp -rT /usr/lib/modules "%{install-root}/usr/lib/modules"
      # vmlinux is the unstripped kernel: ~490 MB of debug data. Runtime
      # consumers read /sys/kernel/btf/vmlinux, not this file. The kernel
      # element declares it in the debug domain, but the copy above flattens
      # the domains, so the image compose's `exclude: [devel, debug]` no longer
      # recognises it. Re-declaring the domain on this element did not remove
      # it from the composed image — the published image's compressed size was
      # unchanged — so remove it outright.
      rm -f "%{install-root}/usr/lib"/modules/*/vmlinux
    - |
      # 25.08 kernels install vmlinuz to /boot; 26.08 kernels ship it inside
      # /usr/lib/modules/<ver>/ already. Handle both, then prove it is there.
      version="$(ls -1 /usr/lib/modules | head -n1)"
      if [ -f /boot/vmlinuz ]; then
        cp /boot/vmlinuz "%{install-root}/usr/lib/modules/${version}"
      fi
      test -f "%{install-root}/usr/lib/modules/${version}/vmlinuz"
