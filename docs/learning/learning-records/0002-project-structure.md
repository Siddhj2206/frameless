# BuildStream project structure: `include/` and `plugins/`

The user asked what `include/` and `plugins/` are for, and whether the Bluefin
repos use custom plugins. Now established:

- `include/` is a project convention, not a BuildStream requirement: shared YAML
  fragments pulled in with the `(@)` directive.
- `plugins/` is for project-local Python plugins, registered as
  `origin: local, path: plugins`. Only dakota has one (`chunkah-ownership`); it
  is repo-specific and out of scope for frameless.
- Junctions are windows with overrides, not copies — the reason
  `gnome-build-meta.bst` overrides `freedesktop-sdk.bst`.

Implication: frameless ships no `plugins/` and keeps `custom/` unwired until the
seam ticket. Future lessons can assume this vocabulary.
