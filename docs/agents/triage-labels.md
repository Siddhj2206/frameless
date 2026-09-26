# Triage Labels

The skills speak in terms of five canonical triage roles. This file maps those roles to the labels used in this repo's tracker.

This repo follows projectbluefin's seven-label contract: `1-triage`, `2-discussing`, `3-human-queue`, `3-clanker-queue`, `4-review`, `blocked`, `hold`. There is no `wontfix` label in that contract, so the `wontfix` role closes the issue instead.

| Label in mattpocock/skills | Label in our tracker | Meaning                                          |
| -------------------------- | -------------------- | ------------------------------------------------ |
| `needs-triage`             | `1-triage`           | Maintainer needs to evaluate this issue          |
| `needs-info`               | `2-discussing`       | Waiting on reporter for more information         |
| `ready-for-agent`          | `3-clanker-queue`    | Fully specified, ready for an AFK agent          |
| `ready-for-human`          | `3-human-queue`      | Requires human implementation                    |
| `wontfix`                  | _(close the issue)_  | Will not be actioned                             |

`blocked` and `hold` are overlays and stay available alongside the mapped label.

When a skill mentions a role (e.g. "apply the AFK-ready triage label"), use the corresponding label string from this table.

Edit the right-hand column to match whatever vocabulary you actually use.
