# elements

The image graph. Every `.bst` file here is a BuildStream **element** — a node
that either builds something or groups other elements.

Start with `image/deps.bst`: it is both the manifest and the map.

| Path | What it is |
|---|---|
| `freedesktop-sdk.bst` | junction — the OS |
| `gnome-build-meta.bst` | junction — the desktop |
| `plugins/` | junction — the BuildStream plugin packages (not the local plugin; that is `../plugins/`) |
| `desktop/gnome.bst` | the desktop layer. Swap this element for KDE, niri, or nothing. |
| `runtime/` | the bundled ublue runtime: ujust, Homebrew, first-boot units |
| `custom/custom.bst` | installs the `custom/` tree — the adopter's declarations |
| `kernel/unsigned-modules.bst` | overrides an upstream element that cannot load in a fork |
| `oci/` | the OCI image: the layers, the os-release element, and the default target |
| `core/sandbox-tools.bst` | the shell every element's build sandbox needs |
| `image/deps.bst` | the manifest: what goes into the image |

An element's `depends:` is its runtime closure — what ends up in the image.
`build-depends:` is staged into the sandbox only while it builds.

New to the vocabulary? Read the `buildstream` skill.
