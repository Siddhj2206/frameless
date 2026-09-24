# ujust

Recipes here become the image's `ujust` commands. Every `.just` file in this
directory tree is concatenated into `/usr/share/ublue-os/just/60-custom.just` at
build time, and Common's `/usr/share/ublue-os/just/00-entry.just` imports that
file. The search is recursive, so recipes can be grouped into subdirectories by
topic.

## Files

- `custom-apps.just` — Homebrew shortcuts
- `custom-system.just` — system configuration

## Writing a recipe

```just
# Install the default applications via Homebrew
[group('Apps')]
install-default-apps:
    #!/usr/bin/env bash
    set -euo pipefail
    brew bundle --file /usr/share/ublue-os/homebrew/default.Brewfile
```

- `[group('…')]` puts the recipe in a section of `ujust --list`.
- Use a bash shebang for anything past one line, and `set -euo pipefail`.
- Name with a verb prefix: `install-`, `configure-`, `setup-`, `toggle-`, `fix-`.
- Prefer plain bash and `read` for prompts. `gum` may not be present; guard with
  `command -v gum` if you use it.

## The rules

- **No package installation.** The image is immutable, so `dnf5` and `rpm` do
  not belong in a recipe. Install software at build time, or point at a
  Brewfile, a Flatpak, or a container.
- Recipes run as the invoking user. Escalate with `sudo` or `pkexec` only where
  the step needs it.
- Nothing here runs automatically. An image update never rewrites a user's
  configuration or changes their groups — these recipes are the explicit way to
  do both.

## Testing

`just check` parses every `.just` file, so a syntax error fails before the build.
To try a recipe's logic without building, run it against the file directly:

```bash
just --justfile custom/ujust/custom-apps.just --list
```

To see it in the image, build (`just bst build oci/image.bst`), boot the result,
then run `ujust`.
