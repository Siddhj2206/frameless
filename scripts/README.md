# scripts

Repository tooling. Nothing here is image content.

| Script | What it does | Run it with |
|---|---|---|
| `validate-brewfiles.sh` | checks `custom/brew/*.Brewfile` without evaluating Ruby | `just validate-brewfiles` |
| `validate-flatpaks.sh` | checks `custom/flatpaks/*.preinstall` against Flathub | `just validate-flatpaks` |
| `ownership_metadata.py` | chunkah ownership: verifies the basis, finalizes it into the image, and binds it to the exported image | called by `elements/oci/image.bst` and `just export` / `just chunkify` |

Each validator is the single implementation of its check: CI and the pre-commit
hook call the same script, so there is nothing to keep in sync.
