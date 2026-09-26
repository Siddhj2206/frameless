# The custom/ seam: declarations versus content

The adopter-facing seam is one element — `elements/custom/custom.bst` reads the
whole `custom/` tree with a single `kind: local` source — so the rule for a fork
is "put it in `custom/`, rebuild". Verified the adopter loop end to end: the
Brewfiles and preinstalls validate, `just check` parses the recipes, and a
recipe's justfile lists locally without a build.

The durable distinction this ticket settled: **content versus declaration**.
A package the image needs is *content* and belongs in the `elements/image/deps.bst`
element stack. A Brewfile, a Flatpak preinstall, or a ujust recipe is a
*declaration* the runtime reads, and belongs in `custom/`. `custom/files/` and
`custom/config/` are the two seams that are copied in directly.

Two finpilot claims were false for frameless and are gone: there is no shipped
`gum` and no `/usr/lib/ujust/ujust.sh`; and the Flathub remote is provided by the
GNOME OS base (`gnomeos-deps/flathub-config.bst`), not fetched by our build. The
`customize` skill was rewritten from the dnf5/Containerfile model to this one.
