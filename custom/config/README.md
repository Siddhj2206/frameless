# custom/config

Per-user configuration, seeded into the `~/.config/` of every new user.

Files here are copied to `/etc/skel/.config/` at build time, so accounts created
after the build start with them. Existing users are left alone: rewriting a home
directory on every boot would discard their edits, so updating a user who
already exists is the `ujust install-config` command, never an automatic login
hook.

`elements/custom/custom.bst` copies this directory into `/etc/skel/.config/`
after `custom/files/`, so a file here also wins over an inherited one — including
the `/etc/skel/.config/` files that Common's shared layer ships. Overriding that
way is intended.

`custom/files/` is the seam for system payloads outside `~/.config/`. The
`customize` skill decides which seam a given file belongs in.

`environment.d/10-example.conf` is the shipped example: inert as written, and
safe to replace.
