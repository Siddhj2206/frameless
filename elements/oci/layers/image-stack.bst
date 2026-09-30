###############################################################################
# OCI layer: the composed root
###############################################################################
# The stack that becomes the image's filesystem. It pulls the image manifest
# together with the boot/initramfs/config elements a bootc image needs, then
# lays out the bootc filesystem in integration commands (which run after all
# staging, so they are the deterministic winner).
###############################################################################
kind: stack

depends:
  - image/deps.bst
  - oci/os-release.bst

  - freedesktop-sdk.bst:components/linux-firmware.bst
  - gnome-build-meta.bst:gnomeos/initramfs/signed-modules.bst
  - gnome-build-meta.bst:oci/initramfs/image.bst

  - gnome-build-meta.bst:gnomeos-deps/bootc.bst
  - gnome-build-meta.bst:oci/integration/bootc-config.bst
  - freedesktop-sdk.bst:vm/config/useradd-default.bst
  - freedesktop-sdk.bst:vm/config/sudo.bst

public:
  bst:
    integration-commands:
      # The bootc filesystem layout. Wipe the build-time /var and the FHS
      # directories that must be symlinks into it, then recreate the
      # structure bootc expects. Relative symlinks match the upstream images.
      - rm -rfv /boot /run

      - mkdir /boot
      - mkdir /run
      - mkdir /sysroot
      - mkdir /sysroot/ostree

      # Remove the link paths before linking, and use -T so the link name is
      # exact. `ln -s TARGET LINK` nests *inside* LINK when LINK is an existing
      # directory, and FSDK's runtime ships /opt, /mnt, /srv and /usr/local as
      # real directories — so without this the image keeps them as directories
      # with junk symlinks inside, instead of the /var symlinks bootc expects.
      # Same rule as dakota's oci/layers/bluefin-stack.bst.
      - rm -rfv /home /root /opt /mnt /srv /var /ostree /usr/local
      - mkdir /home /root /snap
      - mkdir -p /var/home /var/roothome /var/opt /var/mnt /var/srv /var/tmp
      - ln -sT sysroot/ostree /ostree
      - ln -sT var/opt /opt
      - ln -sT var/mnt /mnt
      - ln -sT var/srv /srv
      - ln -sT ../var/usrlocal /usr/local

      - touch /etc/machine-id
