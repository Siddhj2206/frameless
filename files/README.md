# files

The template's own local source payloads, referenced by elements as
`kind: local, path: files/…`.

Two kinds live here:

- **Installed into the image** — `firstboot/` (the first-boot units) and
  `service-overrides/` (the flatpak-preinstall condition), consumed by
  `elements/runtime/firstboot.bst`.
- **Host tooling, never in the image** — `fakecap/*.c`, compiled by the
  `just chunkify` recipe to restore xattrs while rechunking.

These belong to the template's implementation: you touch them when you change an
element, not when you make the image yours.

To add image content without editing an element, use `custom/files/` instead — it
mirrors `/` and `elements/custom/custom.bst` copies it in. The `customize` skill
decides which of the two a given file belongs in.
