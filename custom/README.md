# custom/ — make the image yours

Everything you change about the **runtime** lives here. One element,
`elements/custom/custom.bst`, installs this whole tree at build time, so the rule
is simple: put it in `custom/`, rebuild, done. You never edit an element to
change your image.

| Directory | Lands at | For |
| --- | --- | --- |
| `custom/brew/*.Brewfile` | `/usr/share/ublue-os/homebrew/` | CLI tools users install on demand |
| `custom/ujust/**/*.just` | `/usr/share/ublue-os/just/60-custom.just` | `ujust` commands |
| `custom/flatpaks/*.preinstall` | `/usr/share/flatpak/preinstall.d/` | GUI apps, installed on first boot |
| `custom/files/` | `/` (the tree mirrors the filesystem root) | system units, presets, tmpfiles.d |
| `custom/config/` | `/etc/skel/.config/` | config for new accounts |

The `README.md` files under `custom/` document each seam. They are excluded from
the image, so they cost nothing at runtime.

## Packages are not custom/

A **package** — something the image needs to boot or run — does not belong here.
Packages are elements in the `elements/image/deps.bst` stack. `custom/` is for
declarations the *runtime* reads, not for image content. The `customize` skill
decides which side a given thing is on.

## What actually installs

Only `custom/files/` and `custom/config/` are copied into the image directly.
Brewfiles and preinstalls are declarations: the image ships them and the runtime
acts on them — on demand for Homebrew, on first boot for Flatpak. An empty
directory is fine.

## The seam is one element

`elements/custom/custom.bst` reads this tree with a single `kind: local` source
and installs each seam. That is deliberate: one place to look, one element to
rebuild, and no element edits when you only want to add a recipe. If you outgrow
it, split the element per seam — BuildStream will cache each independently — but
for a template the single element is the better ergonomic.
