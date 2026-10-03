# Contributing

Thanks for helping out. frameless is a BuildStream template for building your
own OS image; this repository is the template, not an image.

## Before you open a pull request

Run the same checks CI runs:

```bash
just lint          # shellcheck every tracked script
just check         # Justfile syntax
just test-unit     # the suite
just bst show oci/image.bst --deps none   # if the graph changed
```

Use a [Conventional Commit](https://www.conventionalcommits.org/) message
(`<type>[scope]: <description>`). CI runs `validate`, `validate-bst`, and the
unit tests on every pull request; the image build runs on `main`.

## Where a change goes

| The change is… | Put it in |
| --- | --- |
| Image content: a package, a service, a kernel module | `elements/` — a line in `elements/image/deps.bst`, or a new element |
| The desktop | `elements/desktop/` (swap `gnome.bst` for KDE, niri, or nothing) |
| Something a user chooses: a CLI tool, a GUI app, a `ujust` command | `custom/` |
| The local loop or CI | `Justfile` or `.github/workflows/` |

The [`customize`](.agents/skills/customize/SKILL.md) skill decides which of these
a given package belongs in. New to BuildStream? Start with the
[`buildstream`](.agents/skills/buildstream/SKILL.md) skill.

## Upstream is read-only

This repository consumes `freedesktop-sdk`, `gnome-build-meta`,
`projectbluefin/common`, and `ublue-os/brew` through junctions and sources. Keep
changes here. If something belongs upstream, send it upstream.

## Durable learning

When a fix was non-obvious, put it in the skill that owns the area, in the same
pull request. Findings from reading or scouting go in `docs/research/`; the
learning track lives in `docs/learning/`. `CONTEXT.md` is the canonical glossary.

## Triage

This repository uses the shared
[label workflow](https://github.com/projectbluefin/common/blob/main/docs/skills/label-workflow.md):
humans triage and approve, and agents work only on assigned or
`3-clanker-queue` issues.
